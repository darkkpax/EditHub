#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

APP_NAME="${APP_NAME:-Video Downloader}"
EXECUTABLE_NAME="${EXECUTABLE_NAME:-Video Downloader}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.local.VideoDownloader}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
APP_BUNDLE_PATH="$OUTPUT_DIR/$APP_NAME.app"

ICON_CANDIDATES=(
    "${ICON_PATH:-}"
    "$ROOT_DIR/Packaging/macOS/AppIcon.icns"
    "$ROOT_DIR/Assets/AppIcon.icns"
    "$ROOT_DIR/Resources/AppIcon.icns"
)

find_icon() {
    local candidate
    for candidate in "${ICON_CANDIDATES[@]}"; do
        [[ -n "$candidate" ]] || continue
        [[ -f "$candidate" ]] && printf '%s\n' "$candidate" && return 0
    done
    return 1
}

mkdir -p "$OUTPUT_DIR"

echo "Building Swift package ($CONFIGURATION)..."
swift build -c "$CONFIGURATION" --product "$EXECUTABLE_NAME"

BIN_DIR="$(swift build -c "$CONFIGURATION" --product "$EXECUTABLE_NAME" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/$EXECUTABLE_NAME"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
    echo "Executable not found: $EXECUTABLE_PATH" >&2
    exit 1
fi

rm -rf "$APP_BUNDLE_PATH"
mkdir -p "$APP_BUNDLE_PATH/Contents/MacOS" "$APP_BUNDLE_PATH/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_BUNDLE_PATH/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_BUNDLE_PATH/Contents/MacOS/$EXECUTABLE_NAME"

INFO_TEMPLATE="$ROOT_DIR/Packaging/macOS/Info.plist.template"
INFO_PLIST="$APP_BUNDLE_PATH/Contents/Info.plist"

if [[ ! -f "$INFO_TEMPLATE" ]]; then
    echo "Missing Info.plist template: $INFO_TEMPLATE" >&2
    exit 1
fi

sed \
    -e "s|__APP_NAME__|$APP_NAME|g" \
    -e "s|__EXECUTABLE_NAME__|$EXECUTABLE_NAME|g" \
    -e "s|__BUNDLE_IDENTIFIER__|$BUNDLE_IDENTIFIER|g" \
    -e "s|__VERSION__|$VERSION|g" \
    -e "s|__BUILD_NUMBER__|$BUILD_NUMBER|g" \
    "$INFO_TEMPLATE" > "$INFO_PLIST"

if ICON_PATH_RESOLVED="$(find_icon)"; then
    cp "$ICON_PATH_RESOLVED" "$APP_BUNDLE_PATH/Contents/Resources/AppIcon.icns"
    echo "Using icon: $ICON_PATH_RESOLVED"
else
    echo "Icon not found. Put AppIcon.icns into Packaging/macOS/AppIcon.icns or pass ICON_PATH=/path/to/AppIcon.icns"
fi

if command -v codesign >/dev/null 2>&1; then
    SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
    CODESIGN_ARGS=(--force --deep --sign "$SIGN_IDENTITY")

    if [[ -n "${CODESIGN_OPTIONS:-}" ]]; then
        CODESIGN_ARGS+=(--options "$CODESIGN_OPTIONS")
    fi

    codesign "${CODESIGN_ARGS[@]}" "$APP_BUNDLE_PATH" >/dev/null
fi

echo "Built app bundle:"
echo "$APP_BUNDLE_PATH"
