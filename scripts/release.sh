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

BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/release}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"
PROJECT_FILE="$PROJECT_PATH/project.pbxproj"

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

decode_base64_cmd() {
  if base64 --help 2>/dev/null | grep -q -- "--decode"; then
    printf "base64 --decode"
  else
    printf "base64 -D"
  fi
}

VERSION="${VERSION:-$(get_version)}"
SAFE_VERSION="$(printf "%s" "$VERSION" | tr ' /' '--')"
SAFE_NAME="$(printf "%s" "${APP_NAME%.app}" | tr ' /' '--')"

APP_SOURCE="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME"
APP_DIST_PATH="$DIST_DIR/$APP_NAME"
DMG_PATH="$DIST_DIR/${SAFE_NAME}-${SAFE_VERSION}.dmg"
PKG_STAGE="$BUILD_DIR/dmg-stage"
PAYLOAD_TAR="$BUILD_DIR/${SAFE_NAME}-${SAFE_VERSION}.tar.gz"
INSTALLER_PATH="$DIST_DIR/${SAFE_NAME}-${SAFE_VERSION}-installer.sh"
BASE64_DECODE_CMD="$(decode_base64_cmd)"

echo "Preparing clean build folders..."
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

echo "Building app ($SCHEME, $CONFIGURATION)..."
BUILD_LOG="$BUILD_DIR/xcodebuild.log"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build | tee "$BUILD_LOG"

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "Build completed but app was not found: $APP_SOURCE" >&2
  exit 1
fi

echo "Copying app bundle..."
cp -R "$APP_SOURCE" "$APP_DIST_PATH"

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

echo "Creating self-extracting shell installer..."
LC_ALL=C tar -C "$DIST_DIR" -czf "$PAYLOAD_TAR" "$APP_NAME"
cat >"$INSTALLER_PATH" <<EOF
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="$APP_NAME"
INSTALL_DIR="\${INSTALL_DIR:-/Applications}"
TMP_DIR="\$(mktemp -d)"
trap 'rm -rf "\$TMP_DIR"' EXIT

extract_payload() {
  local payload_line
  payload_line="\$(awk '/^__PAYLOAD_BELOW__/ { print NR + 1; exit 0; }' "\$0")"
  tail -n "+\${payload_line}" "\$0" | $BASE64_DECODE_CMD > "\$TMP_DIR/payload.tar.gz"
}

install_app() {
  local app_source="\$TMP_DIR/\$APP_NAME"
  local app_target="\$INSTALL_DIR/\$APP_NAME"

  if [[ ! -d "\$app_source" ]]; then
    echo "Installer payload is missing \$APP_NAME." >&2
    exit 1
  fi

  if rm -rf "\$app_target" 2>/dev/null && cp -R "\$app_source" "\$INSTALL_DIR/" 2>/dev/null; then
    echo "Installed \$APP_NAME to \$INSTALL_DIR."
    return 0
  fi

  echo "Requesting admin permission to finish install..."
  sudo rm -rf "\$app_target"
  sudo cp -R "\$app_source" "\$INSTALL_DIR/"
  echo "Installed \$APP_NAME to \$INSTALL_DIR."
}

extract_payload
LC_ALL=C tar -xzf "\$TMP_DIR/payload.tar.gz" -C "\$TMP_DIR"
install_app
exit 0
__PAYLOAD_BELOW__
EOF

base64 <"$PAYLOAD_TAR" >>"$INSTALLER_PATH"
chmod +x "$INSTALLER_PATH"

echo
echo "Release artifacts created:"
echo "  App:       $APP_DIST_PATH"
echo "  DMG:       $DMG_PATH"
echo "  Installer: $INSTALLER_PATH"
echo
echo "Notes:"
echo "  - This build is unsigned (CODE_SIGNING_ALLOWED=NO)."
echo "  - For public distribution without security warnings, use Developer ID signing + notarization."
