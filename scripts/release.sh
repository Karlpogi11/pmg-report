#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/Report Template/Report Template.xcodeproj}"
SCHEME="${SCHEME:-Report Template}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-Report Template.app}"
VOL_NAME="${VOL_NAME:-Report Template}"
HOST_ARCH="$(uname -m)"
DESTINATION="${DESTINATION:-platform=macOS,arch=$HOST_ARCH}"
PROJECT_FILE="$PROJECT_PATH/project.pbxproj"
APP_INFO_PLIST_SOURCE="${APP_INFO_PLIST_SOURCE:-$ROOT_DIR/Info.plist}"

BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/release}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"
PKG_STAGE="$BUILD_DIR/dmg-stage"
BUILD_LOG="$BUILD_DIR/xcodebuild.log"
PRODUCTION_RELEASE="${PRODUCTION_RELEASE:-0}"
VERIFY_RELEASE_ARTIFACTS="${VERIFY_RELEASE_ARTIFACTS:-1}"

SPARKLE_ENABLED="${SPARKLE_ENABLED:-1}"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-KarlApp.Report-Template}"
SPARKLE_CHECKOUT="${SPARKLE_CHECKOUT:-}"
SPARKLE_TOOLS_DERIVED_DATA="$BUILD_DIR/SparkleToolsDerivedData"
APPCAST_FILE_NAME="${APPCAST_FILE_NAME:-appcast.xml}"
COPY_APPCAST_TO_ROOT="${COPY_APPCAST_TO_ROOT:-1}"
SPARKLE_CODESIGN_IDENTITY="${SPARKLE_CODESIGN_IDENTITY:--}"
if [[ "$PRODUCTION_RELEASE" == "1" ]]; then
  SPARKLE_ALLOW_KEY_GENERATION_DEFAULT="0"
else
  SPARKLE_ALLOW_KEY_GENERATION_DEFAULT="1"
fi
SPARKLE_ALLOW_KEY_GENERATION="${SPARKLE_ALLOW_KEY_GENERATION:-$SPARKLE_ALLOW_KEY_GENERATION_DEFAULT}"
SPARKLE_PRIVATE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-}"
SPARKLE_PRIVATE_KEY_BASE64="${SPARKLE_PRIVATE_KEY_BASE64:-}"
DEVELOPER_ID_APP_IDENTITY="${DEVELOPER_ID_APP_IDENTITY:-}"
NOTARIZE_ENABLED="${NOTARIZE_ENABLED:-auto}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
NOTARY_TEAM_ID="${NOTARY_TEAM_ID:-}"

get_version() {
  local version
  version="$(
    awk -F' = ' '/MARKETING_VERSION = / {
      gsub(/;|"/, "", $2);
      print $2;
      exit
    }' "$PROJECT_FILE"
  )"

  if [[ -n "$version" ]]; then
    printf "%s\n" "$version"
    return 0
  fi

  git -C "$ROOT_DIR" rev-parse --short HEAD
}

VERSION="${VERSION:-$(get_version)}"
SAFE_VERSION="$(printf "%s" "$VERSION" | tr ' /' '--')"
SAFE_NAME="$(printf "%s" "${APP_NAME%.app}" | tr ' /' '--')"
RELEASE_TAG="${RELEASE_TAG:-v$VERSION}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/Karlpogi11/pmg-report/releases/download/$RELEASE_TAG/}"
if [[ "$DOWNLOAD_URL_PREFIX" != */ ]]; then
  DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX}/"
fi

APP_SOURCE="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME"
APP_DIST_PATH="$DIST_DIR/$APP_NAME"
DMG_PATH="$DIST_DIR/${SAFE_NAME}-${SAFE_VERSION}.dmg"
APPCAST_DIST_PATH="$DIST_DIR/$APPCAST_FILE_NAME"
APPCAST_ROOT_PATH="$ROOT_DIR/$APPCAST_FILE_NAME"
APPCAST_STAGE="$BUILD_DIR/appcast-stage"
NOTARY_APP_ZIP_PATH="$BUILD_DIR/${SAFE_NAME}-${SAFE_VERSION}.zip"
SPARKLE_TEMP_PRIVATE_KEY_FILE="$BUILD_DIR/sparkle-private-key.txt"

run_with_retry() {
  local attempts="$1"
  shift

  local attempt=1
  until "$@"; do
    if (( attempt >= attempts )); then
      return 1
    fi
    echo "Command failed (attempt $attempt/$attempts). Retrying in 5s..."
    attempt=$((attempt + 1))
    sleep 5
  done
}

normalize_bool() {
  local value="$1"
  case "$value" in
    1|true|TRUE|yes|YES) printf "1\n" ;;
    0|false|FALSE|no|NO) printf "0\n" ;;
    *)
      echo "Boolean flag value must be one of: 1,0,true,false,yes,no (got '$value')." >&2
      exit 1
      ;;
  esac
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command '$command_name' was not found in PATH." >&2
    exit 1
  fi
}

read_plist_value() {
  local plist_path="$1"
  local key="$2"

  if [[ ! -f "$plist_path" ]]; then
    return 1
  fi

  /usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" 2>/dev/null
}

decode_base64_env_to_file() {
  local env_name="$1"
  local output_path="$2"

  python3 - "$env_name" "$output_path" <<'PY'
import base64
import os
import sys

env_name = sys.argv[1]
output_path = sys.argv[2]
payload = os.environ.get(env_name, "").strip()
if not payload:
    raise SystemExit(f"{env_name} is empty")
decoded = base64.b64decode(payload, validate=True)
with open(output_path, "wb") as f:
    f.write(decoded)
PY
}

ensure_required_tools() {
  require_command xcodebuild
  require_command codesign
  require_command hdiutil
  require_command python3
  require_command xcrun
  require_command security
}

discover_sparkle_checkout() {
  local candidate
  for candidate in "$HOME"/Library/Developer/Xcode/DerivedData/*/SourcePackages/checkouts/Sparkle; do
    if [[ -f "$candidate/Sparkle.xcodeproj/project.pbxproj" ]]; then
      printf "%s\n" "$candidate"
      return 0
    fi
  done
  return 1
}

build_sparkle_tool() {
  local scheme="$1"
  xcodebuild \
    -project "$SPARKLE_CHECKOUT/Sparkle.xcodeproj" \
    -scheme "$scheme" \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "$SPARKLE_TOOLS_DERIVED_DATA" \
    build >"$BUILD_DIR/${scheme}.log"
}

ensure_sparkle_tools() {
  if [[ -z "$SPARKLE_CHECKOUT" ]]; then
    if ! SPARKLE_CHECKOUT="$(discover_sparkle_checkout)"; then
      echo "Unable to locate Sparkle source checkout in Xcode DerivedData." >&2
      echo "Open/build the app in Xcode once to fetch package checkouts, or set SPARKLE_CHECKOUT manually." >&2
      exit 1
    fi
  fi

  if [[ ! -f "$SPARKLE_CHECKOUT/Sparkle.xcodeproj/project.pbxproj" ]]; then
    echo "Invalid SPARKLE_CHECKOUT: $SPARKLE_CHECKOUT" >&2
    exit 1
  fi

  GENERATE_KEYS_BIN="$SPARKLE_TOOLS_DERIVED_DATA/Build/Products/Release/generate_keys"
  GENERATE_APPCAST_BIN="$SPARKLE_TOOLS_DERIVED_DATA/Build/Products/Release/generate_appcast"

  if [[ ! -x "$GENERATE_KEYS_BIN" || ! -x "$GENERATE_APPCAST_BIN" ]]; then
    echo "Building Sparkle publishing tools..."
    build_sparkle_tool generate_keys
    build_sparkle_tool generate_appcast
  fi

  if [[ ! -x "$GENERATE_KEYS_BIN" || ! -x "$GENERATE_APPCAST_BIN" ]]; then
    echo "Sparkle tools were not produced as expected." >&2
    exit 1
  fi
}

ensure_sparkle_key() {
  local public_key
  if public_key="$("$GENERATE_KEYS_BIN" -p --account "$SPARKLE_KEY_ACCOUNT" 2>/dev/null)"; then
    printf "%s\n" "$public_key"
    return 0
  fi

  if import_sparkle_private_key_from_env; then
    if public_key="$("$GENERATE_KEYS_BIN" -p --account "$SPARKLE_KEY_ACCOUNT" 2>/dev/null)"; then
      printf "%s\n" "$public_key"
      return 0
    fi
    echo "Sparkle private key import completed but key lookup still failed for account '$SPARKLE_KEY_ACCOUNT'." >&2
    exit 1
  fi

  if [[ "$SPARKLE_ALLOW_KEY_GENERATION" == "1" ]]; then
    echo "No Sparkle key found for account '$SPARKLE_KEY_ACCOUNT'. Generating one..."
    "$GENERATE_KEYS_BIN" --account "$SPARKLE_KEY_ACCOUNT"
    "$GENERATE_KEYS_BIN" -p --account "$SPARKLE_KEY_ACCOUNT"
    return 0
  fi

  echo "No Sparkle key found for account '$SPARKLE_KEY_ACCOUNT' and SPARKLE_ALLOW_KEY_GENERATION=0." >&2
  echo "Provide SPARKLE_PRIVATE_KEY_FILE or SPARKLE_PRIVATE_KEY_BASE64 to import the existing private key." >&2
  exit 1
}

import_sparkle_private_key_from_env() {
  local private_key_file=""
  local imported=0
  local temporary_private_key_file=0

  if [[ -n "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
    if [[ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
      echo "SPARKLE_PRIVATE_KEY_FILE does not exist: $SPARKLE_PRIVATE_KEY_FILE" >&2
      exit 1
    fi
    private_key_file="$SPARKLE_PRIVATE_KEY_FILE"
    imported=1
  elif [[ -n "$SPARKLE_PRIVATE_KEY_BASE64" ]]; then
    rm -f "$SPARKLE_TEMP_PRIVATE_KEY_FILE"
    decode_base64_env_to_file "SPARKLE_PRIVATE_KEY_BASE64" "$SPARKLE_TEMP_PRIVATE_KEY_FILE"
    private_key_file="$SPARKLE_TEMP_PRIVATE_KEY_FILE"
    temporary_private_key_file=1
    imported=1
  fi

  if [[ "$imported" == "0" ]]; then
    return 1
  fi

  echo "Importing Sparkle private key for account '$SPARKLE_KEY_ACCOUNT'..."
  "$GENERATE_KEYS_BIN" -f "$private_key_file" --account "$SPARKLE_KEY_ACCOUNT"
  if [[ "$temporary_private_key_file" == "1" ]]; then
    rm -f "$private_key_file"
  fi
  return 0
}

verify_sparkle_public_key_alignment() {
  local expected_public_key
  local bundled_public_key

  expected_public_key="$(read_plist_value "$APP_INFO_PLIST_SOURCE" "SUPublicEDKey" || true)"
  if [[ -z "$expected_public_key" ]]; then
    echo "SUPublicEDKey was not found in source plist: $APP_INFO_PLIST_SOURCE" >&2
    exit 1
  fi

  if [[ "$SPARKLE_PUBLIC_ED_KEY" != "$expected_public_key" ]]; then
    echo "Sparkle key mismatch: keychain account '$SPARKLE_KEY_ACCOUNT' does not match SUPublicEDKey in $APP_INFO_PLIST_SOURCE." >&2
    echo "Expected: $expected_public_key" >&2
    echo "Actual:   $SPARKLE_PUBLIC_ED_KEY" >&2
    exit 1
  fi

  bundled_public_key="$(read_plist_value "$APP_DIST_PATH/Contents/Info.plist" "SUPublicEDKey" || true)"
  if [[ "$bundled_public_key" != "$expected_public_key" ]]; then
    echo "Built app contains an unexpected SUPublicEDKey." >&2
    echo "Expected: $expected_public_key" >&2
    echo "Actual:   ${bundled_public_key:-<missing>}" >&2
    exit 1
  fi
}

resolve_release_mode() {
  PRODUCTION_RELEASE="$(normalize_bool "$PRODUCTION_RELEASE")"
  VERIFY_RELEASE_ARTIFACTS="$(normalize_bool "$VERIFY_RELEASE_ARTIFACTS")"
  SPARKLE_ENABLED="$(normalize_bool "$SPARKLE_ENABLED")"
  COPY_APPCAST_TO_ROOT="$(normalize_bool "$COPY_APPCAST_TO_ROOT")"
  SPARKLE_ALLOW_KEY_GENERATION="$(normalize_bool "$SPARKLE_ALLOW_KEY_GENERATION")"

  if [[ -n "$DEVELOPER_ID_APP_IDENTITY" ]]; then
    SIGNING_MODE="developer_id"
    APP_CODESIGN_IDENTITY="$DEVELOPER_ID_APP_IDENTITY"
  else
    SIGNING_MODE="ad_hoc"
    APP_CODESIGN_IDENTITY="$SPARKLE_CODESIGN_IDENTITY"
  fi

  if [[ "$NOTARIZE_ENABLED" == "auto" ]]; then
    if [[ "$SIGNING_MODE" == "developer_id" ]]; then
      if [[ -n "$NOTARY_KEYCHAIN_PROFILE" ]]; then
        NOTARIZE_ENABLED="1"
      else
        echo "DEVELOPER_ID_APP_IDENTITY is set but NOTARY_KEYCHAIN_PROFILE is missing." >&2
        echo "Set NOTARY_KEYCHAIN_PROFILE for production notarization, or set NOTARIZE_ENABLED=0 to skip notarization intentionally." >&2
        exit 1
      fi
    else
      NOTARIZE_ENABLED="0"
    fi
  fi

  if [[ "$NOTARIZE_ENABLED" != "auto" ]]; then
    NOTARIZE_ENABLED="$(normalize_bool "$NOTARIZE_ENABLED")"
  fi

  if [[ "$NOTARIZE_ENABLED" == "1" && "$SIGNING_MODE" != "developer_id" ]]; then
    echo "NOTARIZE_ENABLED=1 requires DEVELOPER_ID_APP_IDENTITY." >&2
    exit 1
  fi

  if [[ "$NOTARIZE_ENABLED" == "1" && -z "$NOTARY_KEYCHAIN_PROFILE" ]]; then
    echo "NOTARIZE_ENABLED=1 requires NOTARY_KEYCHAIN_PROFILE." >&2
    exit 1
  fi

  if [[ "$PRODUCTION_RELEASE" == "1" ]]; then
    if [[ "$SIGNING_MODE" != "developer_id" ]]; then
      echo "PRODUCTION_RELEASE=1 requires DEVELOPER_ID_APP_IDENTITY." >&2
      exit 1
    fi
    if [[ "$NOTARIZE_ENABLED" != "1" ]]; then
      echo "PRODUCTION_RELEASE=1 requires notarization (set NOTARIZE_ENABLED=1 or auto with NOTARY_KEYCHAIN_PROFILE)." >&2
      exit 1
    fi
    if [[ "$SPARKLE_ENABLED" != "1" ]]; then
      echo "PRODUCTION_RELEASE=1 requires SPARKLE_ENABLED=1 so updates stay consistent." >&2
      exit 1
    fi
    if [[ "$SPARKLE_ALLOW_KEY_GENERATION" == "1" ]]; then
      echo "PRODUCTION_RELEASE=1 requires SPARKLE_ALLOW_KEY_GENERATION=0 to avoid accidental key rotation." >&2
      exit 1
    fi
    VERIFY_RELEASE_ARTIFACTS="1"
  fi
}

ensure_notarization_tools() {
  xcrun --find notarytool >/dev/null
  xcrun --find stapler >/dev/null
}

submit_for_notarization() {
  local artifact_path="$1"
  local args=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
  if [[ -n "$NOTARY_TEAM_ID" ]]; then
    args+=(--team-id "$NOTARY_TEAM_ID")
  fi

  echo "Submitting $(basename "$artifact_path") for notarization..."
  xcrun notarytool submit "$artifact_path" "${args[@]}" --wait
}

sign_app_bundle() {
  if [[ "$SIGNING_MODE" == "developer_id" ]]; then
    echo "Signing app with Developer ID identity..."
    codesign \
      --force \
      --deep \
      --options runtime \
      --timestamp \
      --sign "$APP_CODESIGN_IDENTITY" \
      "$APP_DIST_PATH"
  elif [[ "$SPARKLE_ENABLED" == "1" ]]; then
    echo "Applying ad-hoc signature for Sparkle archive validation..."
    codesign --force --deep --sign "$APP_CODESIGN_IDENTITY" "$APP_DIST_PATH"
  else
    return 0
  fi

  echo "Verifying app signature..."
  codesign --verify --deep --strict --verbose=2 "$APP_DIST_PATH"
}

notarize_and_staple_app() {
  echo "Packaging app for notarization..."
  rm -f "$NOTARY_APP_ZIP_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIST_PATH" "$NOTARY_APP_ZIP_PATH"
  submit_for_notarization "$NOTARY_APP_ZIP_PATH"

  echo "Stapling notarization ticket to app..."
  xcrun stapler staple -v "$APP_DIST_PATH"
}

sign_dmg() {
  if [[ "$SIGNING_MODE" != "developer_id" ]]; then
    return 0
  fi

  echo "Signing DMG with Developer ID identity..."
  codesign \
    --force \
    --timestamp \
    --sign "$APP_CODESIGN_IDENTITY" \
    "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
}

notarize_and_staple_dmg() {
  submit_for_notarization "$DMG_PATH"

  echo "Stapling notarization ticket to DMG..."
  xcrun stapler staple -v "$DMG_PATH"
}

verify_release_artifacts() {
  local dmg_basename
  dmg_basename="$(basename "$DMG_PATH")"

  echo "Running release artifact verification..."
  if [[ ! -d "$APP_DIST_PATH" ]]; then
    echo "App artifact missing: $APP_DIST_PATH" >&2
    exit 1
  fi
  if [[ ! -f "$DMG_PATH" ]]; then
    echo "DMG artifact missing: $DMG_PATH" >&2
    exit 1
  fi

  codesign --verify --deep --strict --verbose=2 "$APP_DIST_PATH"
  hdiutil verify "$DMG_PATH" >/dev/null

  if [[ "$SIGNING_MODE" == "developer_id" ]]; then
    spctl --assess --type exec --verbose=4 "$APP_DIST_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"
  fi

  if [[ "$NOTARIZE_ENABLED" == "1" ]]; then
    xcrun stapler validate -v "$APP_DIST_PATH"
    xcrun stapler validate -v "$DMG_PATH"
  fi

  if [[ "$SPARKLE_ENABLED" == "1" ]]; then
    if [[ ! -f "$APPCAST_DIST_PATH" ]]; then
      echo "Appcast artifact missing: $APPCAST_DIST_PATH" >&2
      exit 1
    fi
    if ! grep -q 'sparkle:edSignature=' "$APPCAST_DIST_PATH"; then
      echo "Appcast does not contain sparkle:edSignature. Sparkle updates will fail signature validation." >&2
      exit 1
    fi
    if ! grep -Fq "$dmg_basename" "$APPCAST_DIST_PATH"; then
      echo "Appcast does not reference expected DMG file '$dmg_basename'." >&2
      exit 1
    fi
  fi
}

ensure_signing_identity_available() {
  if [[ "$SIGNING_MODE" != "developer_id" ]]; then
    return 0
  fi

  if ! security find-identity -v -p codesigning | grep -Fq "$APP_CODESIGN_IDENTITY"; then
    echo "Developer ID identity was not found in available keychains: $APP_CODESIGN_IDENTITY" >&2
    echo "Import the certificate and private key first, then retry." >&2
    exit 1
  fi
}

ensure_required_tools
resolve_release_mode
ensure_signing_identity_available
if [[ "$NOTARIZE_ENABLED" == "1" ]]; then
  ensure_notarization_tools
fi

echo "Preparing clean build folders..."
rm -rf "$DERIVED_DATA_DIR/Build" "$DIST_DIR" "$PKG_STAGE" "$APPCAST_STAGE" "$NOTARY_APP_ZIP_PATH" "$SPARKLE_TEMP_PRIVATE_KEY_FILE"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

echo "Building app ($SCHEME, $CONFIGURATION)..."
run_with_retry 3 bash -o pipefail -c "
  xcodebuild \
    -project \"$PROJECT_PATH\" \
    -scheme \"$SCHEME\" \
    -configuration \"$CONFIGURATION\" \
    -destination \"$DESTINATION\" \
    -derivedDataPath \"$DERIVED_DATA_DIR\" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build | tee \"$BUILD_LOG\"
"

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "Build completed but app was not found: $APP_SOURCE" >&2
  exit 1
fi

echo "Copying app bundle..."
cp -R "$APP_SOURCE" "$APP_DIST_PATH"

sign_app_bundle

if [[ "$NOTARIZE_ENABLED" == "1" ]]; then
  notarize_and_staple_app
fi

echo "Creating DMG..."
rm -rf "$PKG_STAGE"
mkdir -p "$PKG_STAGE"
cp -R "$APP_DIST_PATH" "$PKG_STAGE/$APP_NAME"
ln -s /Applications "$PKG_STAGE/Applications"
hdiutil create \
  -quiet \
  -volname "$VOL_NAME" \
  -srcfolder "$PKG_STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

sign_dmg

if [[ "$NOTARIZE_ENABLED" == "1" ]]; then
  notarize_and_staple_dmg
fi

SPARKLE_PUBLIC_ED_KEY=""
if [[ "$SPARKLE_ENABLED" == "1" ]]; then
  ensure_sparkle_tools
  SPARKLE_PUBLIC_ED_KEY="$(ensure_sparkle_key)"
  verify_sparkle_public_key_alignment

  echo "Generating Sparkle appcast..."
  rm -rf "$APPCAST_STAGE"
  mkdir -p "$APPCAST_STAGE"
  cp "$DMG_PATH" "$APPCAST_STAGE/"

  "$GENERATE_APPCAST_BIN" \
    --account "$SPARKLE_KEY_ACCOUNT" \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    -o "$APPCAST_STAGE/$APPCAST_FILE_NAME" \
    "$APPCAST_STAGE"

  cp "$APPCAST_STAGE/$APPCAST_FILE_NAME" "$APPCAST_DIST_PATH"
  if [[ "$COPY_APPCAST_TO_ROOT" == "1" ]]; then
    cp "$APPCAST_DIST_PATH" "$APPCAST_ROOT_PATH"
  fi
fi

if [[ "$VERIFY_RELEASE_ARTIFACTS" == "1" ]]; then
  verify_release_artifacts
fi

echo
echo "Release artifacts created:"
echo "  App:       $APP_DIST_PATH"
echo "  DMG:       $DMG_PATH"
echo "  Production release: $PRODUCTION_RELEASE"
echo "  Signing mode: $SIGNING_MODE"
if [[ "$SIGNING_MODE" == "developer_id" ]]; then
  echo "  Developer ID identity: $APP_CODESIGN_IDENTITY"
fi
echo "  Notarization enabled: $NOTARIZE_ENABLED"
echo "  Verify artifacts: $VERIFY_RELEASE_ARTIFACTS"
if [[ "$NOTARIZE_ENABLED" == "1" ]]; then
  echo "  Notary profile: $NOTARY_KEYCHAIN_PROFILE"
  if [[ -n "$NOTARY_TEAM_ID" ]]; then
    echo "  Notary team ID: $NOTARY_TEAM_ID"
  fi
fi
if [[ "$SPARKLE_ENABLED" == "1" ]]; then
  echo "  Appcast:   $APPCAST_DIST_PATH"
  if [[ "$COPY_APPCAST_TO_ROOT" == "1" ]]; then
    echo "  Appcast (repo root): $APPCAST_ROOT_PATH"
  fi
  echo "  Sparkle key account: $SPARKLE_KEY_ACCOUNT"
  echo "  Sparkle key generation allowed: $SPARKLE_ALLOW_KEY_GENERATION"
  echo "  SUPublicEDKey: $SPARKLE_PUBLIC_ED_KEY"
fi
echo
echo "Notes:"
echo "  - Build runs with CODE_SIGNING_ALLOWED=NO, then artifacts are signed in dist/."
if [[ "$SIGNING_MODE" == "developer_id" ]]; then
  echo "  - App and DMG are signed with Developer ID Application and hardened runtime."
elif [[ "$SPARKLE_ENABLED" == "1" ]]; then
  echo "  - App bundle is ad-hoc signed for Sparkle archive validation."
fi
if [[ "$NOTARIZE_ENABLED" == "1" ]]; then
  echo "  - App and DMG notarization tickets are stapled."
else
  echo "  - Notarization is disabled."
fi
if [[ "$VERIFY_RELEASE_ARTIFACTS" == "1" ]]; then
  echo "  - Release verification checks passed."
fi
if [[ "$SPARKLE_ENABLED" == "1" ]]; then
  echo "  - Sparkle feed entries point to: $DOWNLOAD_URL_PREFIX"
fi
