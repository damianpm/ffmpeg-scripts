#!/usr/bin/env bash
# Shared helpers for ffmpeg-scripts. Source this file; don't execute it.

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

require_cmd() {
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' is required but not found on PATH."
    done
}

require_file() {
    local f="$1"
    [ -n "$f" ] || die "require_file: empty path."
    [ -e "$f" ] || die "Input not found: $f"
    [ -r "$f" ] || die "Input not readable: $f"
}

# Print a usable font file path on stdout, or exit non-zero.
# Honors the FONTFILE env var if set and readable.
detect_fontfile() {
    if [ -n "${FONTFILE:-}" ]; then
        [ -r "$FONTFILE" ] || die "FONTFILE is set but not readable: $FONTFILE"
        printf '%s' "$FONTFILE"
        return 0
    fi

    local candidates=(
        "/System/Library/Fonts/Supplemental/Arial.ttf"
        "/System/Library/Fonts/Helvetica.ttc"
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
        "/usr/share/fonts/TTF/DejaVuSans.ttf"
        "/usr/share/fonts/dejavu/DejaVuSans.ttf"
        "/usr/share/fonts/liberation/LiberationSans-Regular.ttf"
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"
        "/Library/Fonts/Arial.ttf"
        "C:/Windows/Fonts/arial.ttf"
    )
    local f
    for f in "${candidates[@]}"; do
        [ -r "$f" ] && { printf '%s' "$f"; return 0; }
    done

    if command -v fc-match >/dev/null 2>&1; then
        f=$(fc-match -f '%{file}' sans 2>/dev/null || true)
        [ -n "$f" ] && [ -r "$f" ] && { printf '%s' "$f"; return 0; }
    fi

    die "No usable font found. Set FONTFILE=/path/to/font.ttf to override."
}

# Escape a string for safe use inside an ffmpeg drawtext 'text=...' value.
# Pair with expansion=none on the filter so % is treated literally; we still
# escape \, :, and ' which are filter-graph syntax characters.
escape_drawtext() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//:/\\:}"
    s="${s//\'/\\\\\\\'}"
    printf '%s' "$s"
}
