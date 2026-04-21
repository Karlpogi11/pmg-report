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

VERSION="${VERSION:-$(get_version)}"
SAFE_VERSION="$(printf "%s" "$VERSION" | tr ' /' '--')"
SAFE_NAME="$(printf "%s" "${APP_NAME%.app}" | tr ' /' '--')"

APP_SOURCE="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME"
APP_DIST_PATH="$DIST_DIR/$APP_NAME"
DMG_PATH="$DIST_DIR/${SAFE_NAME}-${SAFE_VERSION}.dmg"
PKG_STAGE="$BUILD_DIR/dmg-stage"

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

echo
echo "Release artifacts created:"
echo "  App:       $APP_DIST_PATH"
echo "  DMG:       $DMG_PATH"
echo
echo "Notes:"
echo "  - This build is unsigned (CODE_SIGNING_ALLOWED=NO)."
echo "  - For public distribution without security warnings, use Developer ID signing + notarization."
