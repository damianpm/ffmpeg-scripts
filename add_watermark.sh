#!/bin/bash

# Usage: ./add_watermark.sh INPUT OUTPUT [TEXT] [POSITION] [COLOR] [FONTSIZE]
# Defaults: TEXT="Watermark", POSITION="bottom-left", COLOR="white", FONTSIZE=12
# Positions: top-left, top-right, bottom-left, bottom-right, center

INPUT="$1"
OUTPUT="$2"
TEXT="${3:-Watermark}"
POSITION="${4:-bottom-left}"
COLOR="${5:-white}"
FONTSIZE="${6:-12}"

if [ $# -lt 2 ]; then
    echo "Usage: $0 INPUT OUTPUT [TEXT] [POSITION] [COLOR] [FONTSIZE]"
    echo "Defaults: TEXT=\"Watermark\", POSITION=\"bottom-left\", COLOR=\"white\", FONTSIZE=12"
    exit 1
fi

# Map position to x,y coordinates
case "$POSITION" in
    "top-left")     X="10"; Y="10" ;;
    "top-right")    X="w-tw-10"; Y="10" ;;
    "bottom-left")  X="10"; Y="h-th-10" ;;
    "bottom-right") X="w-tw-10"; Y="h-th-10" ;;
    "center")       X="(w-tw)/2"; Y="(h-th)/2" ;;
    *)              echo "Error: Invalid position. Use: top-left, top-right, bottom-left, bottom-right, center"; exit 1 ;;
esac

echo "Adding watermark '$TEXT' at $POSITION ($COLOR, ${FONTSIZE}px) to $INPUT"

# Add watermark with drawtext filter (re-encodes video, copies audio)
ffmpeg -y -i "$INPUT" \
    -vf "drawtext=fontcolor=$COLOR:fontsize=$FONTSIZE:text='$TEXT':x=$X:y=$Y:fontfile=/System/Library/Fonts/Arial.ttf" \
    -c:a copy "$OUTPUT" -loglevel error

echo "Watermarked video saved: $OUTPUT"
    