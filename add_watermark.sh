#!/usr/bin/env bash
#
# Add a text watermark to a video using FFmpeg's drawtext filter.
#
# Usage: ./add_watermark.sh INPUT OUTPUT [TEXT] [POSITION] [COLOR] [FONTSIZE]
# Defaults: TEXT="Watermark", POSITION="bottom-left", COLOR="white", FONTSIZE=12
# Positions: top-left, top-right, bottom-left, bottom-right, center
#
# Env: FONTFILE=/path/to/font.ttf  (overrides font auto-detection)

set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<EOF
Usage: $0 INPUT OUTPUT [TEXT] [POSITION] [COLOR] [FONTSIZE]
Defaults: TEXT="Watermark", POSITION="bottom-left", COLOR="white", FONTSIZE=12
Positions: top-left, top-right, bottom-left, bottom-right, center
Env: FONTFILE=/path/to/font.ttf (override font auto-detection)
EOF
}

if [ $# -lt 2 ]; then
    usage
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
TEXT="${3:-Watermark}"
POSITION="${4:-bottom-left}"
COLOR="${5:-white}"
FONTSIZE="${6:-12}"

require_cmd ffmpeg
require_file "$INPUT"

if ! [[ "$FONTSIZE" =~ ^[0-9]+$ ]] || [ "$FONTSIZE" -lt 1 ]; then
    die "FONTSIZE must be a positive integer."
fi

case "$POSITION" in
    top-left)     X="10";        Y="10" ;;
    top-right)    X="w-tw-10";   Y="10" ;;
    bottom-left)  X="10";        Y="h-th-10" ;;
    bottom-right) X="w-tw-10";   Y="h-th-10" ;;
    center)       X="(w-tw)/2";  Y="(h-th)/2" ;;
    *) die "Invalid position '$POSITION'. Use: top-left, top-right, bottom-left, bottom-right, center." ;;
esac

FONTFILE_PATH="$(detect_fontfile)"
ESCAPED_TEXT="$(escape_drawtext "$TEXT")"
ESCAPED_FONT="$(escape_drawtext "$FONTFILE_PATH")"

echo "Adding watermark '$TEXT' at $POSITION ($COLOR, ${FONTSIZE}px) to $INPUT"
echo "Using font: $FONTFILE_PATH"

ffmpeg -y -i "$INPUT" \
    -vf "drawtext=fontfile='${ESCAPED_FONT}':text='${ESCAPED_TEXT}':expansion=none:fontcolor=${COLOR}:fontsize=${FONTSIZE}:x=${X}:y=${Y}" \
    -c:a copy "$OUTPUT" -loglevel error

echo "Watermarked video saved: $OUTPUT"
