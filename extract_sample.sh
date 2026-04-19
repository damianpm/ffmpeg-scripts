#!/usr/bin/env bash
#
# Create a short sample video composed of multiple short segments taken across
# the input video. Useful for preview clips.
#
# Usage:
#   ./extract_sample.sh INPUT TOTAL_SECONDS OUTPUT
#   ./extract_sample.sh INPUT TOTAL_SECONDS NUM_SEGMENTS OUTPUT
#
# TOTAL_SECONDS must be a multiple of 10 (10, 20, 30, ...)
# NUM_SEGMENTS defaults to TOTAL_SECONDS / 10 when omitted.

set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<EOF
Usage: $0 INPUT TOTAL_SECONDS [NUM_SEGMENTS] OUTPUT
TOTAL_SECONDS must be a multiple of 10 (10, 20, 30, ...)
NUM_SEGMENTS is optional (default TOTAL_SECONDS/10)
EOF
}

if [ $# -lt 3 ] || [ $# -gt 4 ]; then
    usage
    exit 1
fi

INPUT="$1"
TOTAL_SECONDS="$2"
if [ $# -eq 3 ]; then
    NUM_SEGMENTS=""
    OUTPUT="$3"
else
    NUM_SEGMENTS="$3"
    OUTPUT="$4"
fi

require_cmd ffmpeg ffprobe
require_file "$INPUT"

if ! [[ "$TOTAL_SECONDS" =~ ^[0-9]+$ ]]; then
    die "TOTAL_SECONDS must be a positive integer (multiple of 10)."
fi
if [ -n "$NUM_SEGMENTS" ] && ! [[ "$NUM_SEGMENTS" =~ ^[0-9]+$ ]]; then
    die "NUM_SEGMENTS must be a positive integer."
fi
if [ "$TOTAL_SECONDS" -lt 10 ] || [ $((TOTAL_SECONDS % 10)) -ne 0 ]; then
    die "TOTAL_SECONDS must be a multiple of 10 (10, 20, 30, ...)."
fi

DURATION=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$INPUT")
[ -n "$DURATION" ] || die "ffprobe could not read duration from '$INPUT'."
# ffprobe may return 'N/A' or similar for unseekable/streaming inputs; require a finite number.
if ! [[ "$DURATION" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    die "ffprobe returned non-numeric duration '$DURATION' for '$INPUT'."
fi
echo "Input video duration: ${DURATION}s"

MAX_POSSIBLE=$(awk "BEGIN {print int($DURATION/10)*10}")
if [ "$MAX_POSSIBLE" -lt 10 ]; then
    die "Input video is shorter than 10s; cannot produce multiple-of-10 sample."
fi

if [ "$TOTAL_SECONDS" -gt "$MAX_POSSIBLE" ]; then
    echo "Requested TOTAL_SECONDS ($TOTAL_SECONDS) is longer than video length; adjusting to $MAX_POSSIBLE"
    TOTAL_SECONDS="$MAX_POSSIBLE"
fi

if [ -z "$NUM_SEGMENTS" ]; then
    NUM_SEGMENTS=$(( TOTAL_SECONDS / 10 ))
fi
if [ "$NUM_SEGMENTS" -lt 1 ]; then
    die "NUM_SEGMENTS must be at least 1."
fi

SEG_PER=$(awk "BEGIN {printf \"%.6f\", $TOTAL_SECONDS / $NUM_SEGMENTS}")

declare -a SEG_DURS
for ((i=0; i<NUM_SEGMENTS-1; i++)); do
    SEG_DURS[i]="$SEG_PER"
done
LAST_DUR=$(awk -v T="$TOTAL_SECONDS" -v N="$NUM_SEGMENTS" -v S="$SEG_PER" \
    'BEGIN{printf "%.6f", T - S*(N-1)}')
SEG_DURS[NUM_SEGMENTS-1]="$LAST_DUR"

SEG_DURS_JOINED=$(IFS=', '; printf '%s' "${SEG_DURS[*]}")
echo "Creating ${NUM_SEGMENTS} segments (durations: ${SEG_DURS_JOINED}) totaling ${TOTAL_SECONDS}s"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT INT TERM
SEGMENT_LIST="$TEMP_DIR/segments.txt"
: > "$SEGMENT_LIST"

# Encode each segment once to MPEG-TS so concat demuxer can stream-copy them.
for ((i=0; i<NUM_SEGMENTS; i++)); do
    SEG_FILE="$TEMP_DIR/seg_${i}.ts"
    DUR="${SEG_DURS[i]}"

    if [ "$i" -eq $((NUM_SEGMENTS - 1)) ]; then
        # Capture the tail precisely to include EOF.
        ffmpeg -y -sseof "-${DUR}" -i "$INPUT" -t "$DUR" \
            -c:v libx264 -preset veryfast -crf 23 \
            -c:a aac -b:a 128k \
            -bsf:v h264_mp4toannexb -f mpegts \
            "$SEG_FILE" -loglevel error
    else
        START_TIME=$(awk -v i="$i" -v D="$DURATION" -v N="$NUM_SEGMENTS" -v S="$DUR" \
            'BEGIN {
                center = (i + 0.5) * D / N;
                start = center - S/2;
                if (start < 0) start = 0;
                if (start > D - S) start = D - S;
                printf "%.3f", start
            }')
        ffmpeg -y -ss "$START_TIME" -i "$INPUT" -t "$DUR" \
            -c:v libx264 -preset veryfast -crf 23 \
            -c:a aac -b:a 128k \
            -bsf:v h264_mp4toannexb -f mpegts \
            "$SEG_FILE" -loglevel error
    fi

    [ -s "$SEG_FILE" ] || die "failed to create segment $SEG_FILE"
    printf "file '%s'\n" "$SEG_FILE" >> "$SEGMENT_LIST"
done

# Stream-copy concat — no second re-encode.
ffmpeg -y -f concat -safe 0 -i "$SEGMENT_LIST" -c copy "$OUTPUT" -loglevel error

ACTUAL_DURATION=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$OUTPUT")
OK=$(awk -v a="$ACTUAL_DURATION" -v b="$TOTAL_SECONDS" \
    'BEGIN{d=a-b; if (d<0) d=-d; print (d <= 0.6) ? 1 : 0}')
if [ "$OK" -eq 1 ]; then
    echo "Sample video created: $OUTPUT (${TOTAL_SECONDS}s total from ${NUM_SEGMENTS} samples)"
else
    echo "Warning: final output duration is ${ACTUAL_DURATION}s; expected ${TOTAL_SECONDS}s"
fi
