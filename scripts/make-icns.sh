#!/bin/zsh

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 /path/to/icon-1024.png [output.icns]" >&2
    exit 1
fi

SOURCE_IMAGE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUTPUT_ICNS="${2:-$(cd "$(dirname "$0")/.." && pwd)/Packaging/macOS/AppIcon.icns}"

if [[ ! -f "$SOURCE_IMAGE" ]]; then
    echo "Source image not found: $SOURCE_IMAGE" >&2
    exit 1
fi

WORK_DIR="$(mktemp -d)"
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    sips -z "$double_size" "$double_size" "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

mkdir -p "$(dirname "$OUTPUT_ICNS")"
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"
rm -rf "$WORK_DIR"

echo "Created icon:"
echo "$OUTPUT_ICNS"
