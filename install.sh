#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-Karlpogi11/pmg-report}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
REQUESTED_VERSION="latest"
AUTO_YES=0

usage() {
  cat <<'EOF'
Usage: install.sh [version] [--yes]

Examples:
  install.sh
  install.sh v1.1
  install.sh --yes
  install.sh v1.1 --yes
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      AUTO_YES=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ "$REQUESTED_VERSION" != "latest" ]]; then
        echo "Only one optional version argument is supported." >&2
        usage
        exit 1
      fi
      REQUESTED_VERSION="$1"
      ;;
  esac
  shift
done

if [[ "$REQUESTED_VERSION" == "latest" ]]; then
  RELEASE_API_URL="https://api.github.com/repos/$REPO/releases/latest"
else
  TAG="$REQUESTED_VERSION"
  if [[ "$TAG" != v* ]]; then
    TAG="v$TAG"
  fi
  RELEASE_API_URL="https://api.github.com/repos/$REPO/releases/tags/$TAG"
fi

TMP_DIR="$(mktemp -d)"
DMG_PATH="$TMP_DIR/app.dmg"
MOUNT_POINT="$TMP_DIR/mount"
ATTACHED=0

cleanup() {
  if [[ "$ATTACHED" -eq 1 ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Fetching release metadata from $REPO..."
curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  "$RELEASE_API_URL" > "$TMP_DIR/release.json"

python3 - "$TMP_DIR/release.json" > "$TMP_DIR/release-info.txt" <<'PY'
import json
import sys

release_path = sys.argv[1]
with open(release_path, "r", encoding="utf-8") as file:
    data = json.load(file)

tag_name = data.get("tag_name")
if not tag_name:
    raise SystemExit("Could not read release tag_name from GitHub API response.")

dmg_asset = None
for asset in data.get("assets", []):
    name = asset.get("name", "")
    url = asset.get("browser_download_url", "")
    if name.endswith(".dmg") and url:
        dmg_asset = (name, url)
        break

if not dmg_asset:
    raise SystemExit("No .dmg asset found in the selected release.")

print(tag_name)
print(dmg_asset[0])
print(dmg_asset[1])
PY

TAG_NAME="$(sed -n '1p' "$TMP_DIR/release-info.txt")"
DMG_NAME="$(sed -n '2p' "$TMP_DIR/release-info.txt")"
DMG_URL="$(sed -n '3p' "$TMP_DIR/release-info.txt")"

if [[ "$REQUESTED_VERSION" == "latest" ]]; then
  INSTALLED_APP_PATH="$INSTALL_DIR/Report Template.app"
  if [[ -d "$INSTALLED_APP_PATH" ]]; then
    INSTALLED_VERSION="$(defaults read "$INSTALLED_APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || true)"
    if [[ -z "$INSTALLED_VERSION" ]]; then
      INSTALLED_VERSION="$(defaults read "$INSTALLED_APP_PATH/Contents/Info.plist" CFBundleVersion 2>/dev/null || true)"
    fi

    if [[ -n "$INSTALLED_VERSION" ]]; then
      if ! python3 - "$TAG_NAME" "$INSTALLED_VERSION" <<'PY'
import re
import sys

def normalize(version: str) -> str:
    version = version.strip()
    if version.lower().startswith("v"):
        return version[1:]
    return version

def to_components(version: str):
    return [int(part) for part in re.split(r"[^0-9]+", normalize(version)) if part]

remote = to_components(sys.argv[1])
local = to_components(sys.argv[2])

if not remote or not local:
    raise SystemExit(0 if normalize(sys.argv[1]) > normalize(sys.argv[2]) else 1)

count = max(len(remote), len(local))
remote += [0] * (count - len(remote))
local += [0] * (count - len(local))

raise SystemExit(0 if remote > local else 1)
PY
      then
        echo "Already up to date (installed: $INSTALLED_VERSION, latest: ${TAG_NAME#v}). Skipping download."
        exit 0
      fi
    fi
  fi
fi

echo "Downloading $DMG_NAME ($TAG_NAME)..."
curl -fL "$DMG_URL" -o "$DMG_PATH"

mkdir -p "$MOUNT_POINT"
hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -quiet
ATTACHED=1

shopt -s nullglob
APP_CANDIDATES=("$MOUNT_POINT"/*.app)
shopt -u nullglob

if [[ "${#APP_CANDIDATES[@]}" -eq 0 ]]; then
  echo "Could not find .app bundle inside mounted DMG." >&2
  exit 1
fi
APP_SOURCE="${APP_CANDIDATES[0]}"

APP_NAME="$(basename "$APP_SOURCE")"
APP_TARGET="$INSTALL_DIR/$APP_NAME"

echo
echo "Ready to install:"
echo "  App:        $APP_NAME"
echo "  Version:    $TAG_NAME"
echo "  Destination:$INSTALL_DIR"

if [[ "$AUTO_YES" -ne 1 ]]; then
  CONFIRM=""
  PROMPT="Continue install? [y/N]"

  if [[ -t 0 ]]; then
    if ! IFS= read -r -p "$PROMPT " CONFIRM; then
      echo "No interactive response detected. Continuing install..."
      CONFIRM="y"
    fi
  elif [[ -t 1 && -e /dev/tty ]]; then
    printf "%s " "$PROMPT" > /dev/tty 2>/dev/null || true
    if ! IFS= read -r CONFIRM < /dev/tty 2>/dev/null; then
      echo "No interactive response detected. Continuing install..."
      CONFIRM="y"
    fi
  else
    echo "No interactive terminal found. Continuing install..."
    CONFIRM="y"
  fi

  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Installation cancelled."
    exit 0
  fi
fi

if rm -rf "$APP_TARGET" 2>/dev/null && ditto "$APP_SOURCE" "$APP_TARGET" 2>/dev/null; then
  echo "Installed $APP_NAME to $INSTALL_DIR."
  exit 0
fi

echo "Requesting admin permission to install into $INSTALL_DIR..."
sudo rm -rf "$APP_TARGET"
sudo ditto "$APP_SOURCE" "$APP_TARGET"
echo "Installed $APP_NAME to $INSTALL_DIR."
