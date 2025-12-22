#!/bin/bash

# Usage: ./extract_sample.sh INPUT TOTAL_SECONDS [NUM_SEGMENTS] OUTPUT
# TOTAL_SECONDS must be a multiple of 10 (10, 20, 30, ...)
# NUM_SEGMENTS is optional (default TOTAL_SECONDS/10); if provided must be a positive integer
# Example: ./extract_sample.sh long_video.mp4 30 4 short_sample.mp4  # 4 segments

INPUT="$1"
TOTAL_SECONDS="$2"
# If 3 args: INPUT TOTAL_SECONDS OUTPUT (NUM_SEGMENTS will be calculated dynamically)
# If 4 args: INPUT TOTAL_SECONDS NUM_SEGMENTS OUTPUT
if [ $# -eq 3 ]; then
    NUM_SEGMENTS=""
    OUTPUT="$3"
else
    NUM_SEGMENTS="$3"
    OUTPUT="$4"
fi

if [ $# -lt 3 ]; then
    echo "Usage: $0 INPUT TOTAL_SECONDS [NUM_SEGMENTS] OUTPUT"
    echo "TOTAL_SECONDS must be a multiple of 10 (10, 20, 30, ...)"
    echo "NUM_SEGMENTS is optional (default TOTAL_SECONDS/10)"
    exit 1
fi

# Validate numeric inputs
if ! [[ "$TOTAL_SECONDS" =~ ^[0-9]+$ ]]; then
    echo "Error: TOTAL_SECONDS must be a positive integer (multiple of 10)"
    exit 1
fi

# If NUM_SEGMENTS was provided, validate it
if [ -n "$NUM_SEGMENTS" ] && ! [[ "$NUM_SEGMENTS" =~ ^[0-9]+$ ]]; then
    echo "Error: NUM_SEGMENTS must be a positive integer"
    exit 1
fi

# Ensure TOTAL_SECONDS is a multiple of 10 and at least 10
if [ "$TOTAL_SECONDS" -lt 10 ] || [ $((TOTAL_SECONDS % 10)) -ne 0 ]; then
    echo "Error: TOTAL_SECONDS must be a multiple of 10 (10, 20, 30, ...)"
    exit 1
fi

# Get video duration in seconds using ffprobe
DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT")
echo "Input video duration: ${DURATION}s"

# Determine maximum possible total duration (multiple of 10) based on input length
MAX_POSSIBLE=$(awk "BEGIN {print int($DURATION/10)*10}")
if [ "$MAX_POSSIBLE" -lt 10 ]; then
    echo "Error: Input video is shorter than 10s; cannot produce multiple-of-10 sample."
    exit 1
fi

if [ "$TOTAL_SECONDS" -gt "$MAX_POSSIBLE" ]; then
    echo "Requested TOTAL_SECONDS ($TOTAL_SECONDS) is longer than video length; adjusting to $MAX_POSSIBLE"
    TOTAL_SECONDS="$MAX_POSSIBLE"
fi

# If NUM_SEGMENTS wasn't provided, choose default = TOTAL_SECONDS / 10
if [ -z "$NUM_SEGMENTS" ]; then
    NUM_SEGMENTS=$(( TOTAL_SECONDS / 10 ))
fi
if [ "$NUM_SEGMENTS" -lt 1 ]; then
    echo "Error: NUM_SEGMENTS must be at least 1"
    exit 1
fi

# Compute equal per-segment durations (using float with high precision); adjust last to ensure sum matches TOTAL_SECONDS
SEG_PER=$(awk "BEGIN {printf \"%.6f\", $TOTAL_SECONDS / $NUM_SEGMENTS}")

declare -a SEG_DURS
for ((i=0; i<NUM_SEGMENTS-1; i++)); do
    SEG_DURS[$i]="$SEG_PER"
done
# last duration = TOTAL_SECONDS - sum(previous)
LAST_DUR=$(awk -v T=$TOTAL_SECONDS -v N=$NUM_SEGMENTS -v S=$SEG_PER 'BEGIN{printf "%.6f", T - S*(N-1)}')
SEG_DURS[$((NUM_SEGMENTS-1))]="$LAST_DUR"

echo "Creating ${NUM_SEGMENTS} segments (durations: ${SEG_DURS[*]}) totaling ${TOTAL_SECONDS}s"

# Create temporary directory for segments
TEMP_DIR=$(mktemp -d)
SEGMENT_LIST="$TEMP_DIR/segments.txt"

> "$SEGMENT_LIST"  # Clear list file

for i in $(seq 0 $((NUM_SEGMENTS - 1))); do
    SEG_FILE="$TEMP_DIR/seg_${i}.mp4"
    DUR=${SEG_DURS[$i]}

    if [ "$i" -eq $((NUM_SEGMENTS - 1)) ]; then
        # Last segment: capture the exact last $DUR seconds to ensure we include EOF
        ffmpeg -y -sseof -$DUR -i "$INPUT" -t "$DUR" -c:v libx264 -preset veryfast -crf 23 -c:a aac -b:a 128k "$SEG_FILE" -loglevel error
    else
        # Compute center-based start and clamp it
        START_TIME=$(awk -v i=$i -v D=$DURATION -v N=$NUM_SEGMENTS -v S=$DUR 'BEGIN { center = (i + 0.5) * D / N; start = center - S/2; if (start < 0) start = 0; if (start > D - S) start = D - S; printf "%.3f", start }')
        ffmpeg -y -i "$INPUT" -ss "$START_TIME" -t "$DUR" -c:v libx264 -preset veryfast -crf 23 -c:a aac -b:a 128k "$SEG_FILE" -loglevel error
    fi

    if [ ! -f "$SEG_FILE" ]; then
        echo "Error: failed to create segment $SEG_FILE"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    echo "file '$SEG_FILE'" >> "$SEGMENT_LIST"
done

# Concatenate segments into final output (re-encode to ensure clean & exact timing)
ffmpeg -y -f concat -safe 0 -i "$SEGMENT_LIST" -c:v libx264 -preset veryfast -crf 23 -c:a aac -b:a 128k "$OUTPUT" -loglevel error

# Verify final duration matches expected TOTAL_SECONDS (allow small tolerance e.g. 0.6s)
ACTUAL_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$OUTPUT")
DIFF=$(awk -v a="$ACTUAL_DURATION" -v b="$TOTAL_SECONDS" 'BEGIN{d=a-b; if (d<0) d=-d; printf "%.3f", d}')
OK=$(awk -v d="$DIFF" 'BEGIN{print (d <= 0.6) ? 1 : 0}')
if [ "$OK" -eq 1 ]; then
    echo "Sample video created: $OUTPUT (${TOTAL_SECONDS}s total from ${NUM_SEGMENTS} samples)"
else
    echo "Warning: final output duration is ${ACTUAL_DURATION}s; expected ${TOTAL_SECONDS}s"
fi

# Cleanup
rm -rf "$TEMP_DIR"
