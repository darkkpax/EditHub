#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

APP_NAME="${APP_NAME:-GoogleDropboxDownloader}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
APP_BUNDLE_PATH="$OUTPUT_DIR/$APP_NAME.app"
DMG_PATH="${DMG_PATH:-$OUTPUT_DIR/$APP_NAME.dmg}"
DMG_VOLUME_NAME="${DMG_VOLUME_NAME:-$APP_NAME}"
STAGING_DIR="$OUTPUT_DIR/.dmg-staging"

"$ROOT_DIR/scripts/build-macos-app.sh"

if [[ ! -d "$APP_BUNDLE_PATH" ]]; then
    echo "App bundle not found: $APP_BUNDLE_PATH" >&2
    exit 1
fi

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

cp -R "$APP_BUNDLE_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$DMG_VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

echo "Built DMG:"
echo "$DMG_PATH"
