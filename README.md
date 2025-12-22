# ffmpeg-scripts 🎬🔧

Small collection of handy FFmpeg helper scripts for working with video files:

- `add_watermark.sh` — add a text watermark to a video
- `extract_sample.sh` — extract a short sample composed of several segments from a longer video

---

## 🔧 Prerequisites

- ffmpeg and ffprobe must be installed and available on PATH.
  - macOS (Homebrew): `brew install ffmpeg`
- Make sure scripts are executable: `chmod +x add_watermark.sh extract_sample.sh`

---

## add_watermark.sh ✅

Add a simple text watermark on top of a video using FFmpeg's `drawtext` filter.

Usage:

```bash
./add_watermark.sh INPUT OUTPUT [TEXT] [POSITION] [COLOR] [FONTSIZE]
```

Defaults:
- TEXT: `Watermark`
- POSITION: `bottom-left` (other options: `top-left`, `top-right`, `bottom-right`, `center`)
- COLOR: `white`
- FONTSIZE: `12`

Example:

```bash
./add_watermark.sh input.mp4 output.mp4 "My Brand" bottom-right yellow 24
```

Notes:
- The script uses the system font at `/System/Library/Fonts/Arial.ttf` (macOS). Update the `fontfile` path in the script if you need a different font or are on another OS.
- The video is re-encoded (video filter applied). Audio is copied as-is.

---

## extract_sample.sh ✂️

Create a short sample video composed of multiple short segments taken across the input video. Useful for preview clips.

Usage:

```bash
# Automatic segments (NUM_SEGMENTS = TOTAL_SECONDS/10):
./extract_sample.sh INPUT TOTAL_SECONDS OUTPUT

# Manually specify number of segments:
./extract_sample.sh INPUT TOTAL_SECONDS NUM_SEGMENTS OUTPUT
```

Rules & behavior:
- `TOTAL_SECONDS` must be a multiple of 10 (10, 20, 30, ...).
- `NUM_SEGMENTS` is optional — if omitted, the script uses `TOTAL_SECONDS / 10`.
- If `TOTAL_SECONDS` is greater than the available video length, it will be adjusted down to the largest multiple of 10 that fits the input.
- The script samples segments spaced across the input (center-based) and concatenates them into the final `OUTPUT` file.

Example:

```bash
# 30 seconds total, split automatically into 3 segments (default)
./extract_sample.sh long_video.mp4 30 sample_short.mp4

# 30 seconds total, force 4 segments
./extract_sample.sh long_video.mp4 30 4 sample_short.mp4
```
