#!/usr/bin/env bash
set -e

# --- Defaults (can be overridden by environment variables) ---
: "${MODEL:=openai/whisper}"

# Check for input file
if [ -z "$1" ]; then
    echo "Usage: $0 input_media"
    echo "The input_media can be either an audio or a video file."
    exit 1
fi

INPUT_MEDIA="$1"
if [ ! -f "$INPUT_MEDIA" ]; then
    echo "Error: Input file '$INPUT_MEDIA' not found."
    exit 1
fi

SHA1="$(sha1sum "$INPUT_MEDIA" | awk '{print $1}')"
INPUT_EXT="${INPUT_MEDIA##*.}"
BASENAME="$(basename "$INPUT_MEDIA" ."$INPUT_EXT")"

# Directories
OUT_DIR="output"
CACHE_DIR="cache/$SHA1"
CACHE_FFMPEG_DIR="$CACHE_DIR/ffmpeg"
CACHE_SPLEETER_DIR="$CACHE_DIR/spleeter"
CACHE_SUBSAI_DIR="$CACHE_DIR/subsai"
CACHE_CONF_DIR="$CACHE_DIR/conf"

# Files (common for both audio and video)
OUTPUT_VIDEO="$CACHE_DIR/${BASENAME}_with_subs.${INPUT_EXT}"
VOCALS_FILE="$CACHE_SPLEETER_DIR/${BASENAME}/vocals.wav"

# Determine if input is video or audio using ffprobe
IS_VIDEO="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_type -of csv=p=0 "$INPUT_MEDIA" 2>/dev/null || true)"

# Subtitle format: SRT for both video and audio
SUBSAI_FORMAT="srt"

if [ "$IS_VIDEO" = "video" ]; then
    # Determine subtitle codec based on container
    case "$INPUT_EXT" in
        mp4|m4v|mov) SRT_CODEC="mov_text" ;;
        mkv|webm)    SRT_CODEC="copy" ;;
        *)           SRT_CODEC="mov_text" ;;
    esac
    SUBTITLE_OUTPUT="$CACHE_SUBSAI_DIR/vocals.srt"
else
    # For audio, we'll still generate SRT files
    SRT_CODEC=""
    SUBTITLE_OUTPUT="$CACHE_SUBSAI_DIR/vocals.srt"
fi

# Create required directories
initialize_directories() {
    mkdir -p "$CACHE_FFMPEG_DIR" "$CACHE_SPLEETER_DIR" "$CACHE_SUBSAI_DIR" "$CACHE_CONF_DIR" "$OUT_DIR"
}

# Run spleeter to separate vocals
run_spleeter() {
    echo "Running Spleeter to separate vocals..."
    spleeter separate "$INPUT_MEDIA" -o "$CACHE_SPLEETER_DIR"
}

# Run subsai to generate subtitles
run_subsai() {
    echo "Running SubSai to generate subtitles..."
    subsai "$VOCALS_FILE" -m "$MODEL" -f "$SUBSAI_FORMAT" -df "$CACHE_SUBSAI_DIR"
}

# Merge subtitles into video
merge_subtitles_video() {
    echo "Merging subtitles into video..."
    if [ "$SRT_CODEC" = "copy" ]; then
        ffmpeg -y -i "$INPUT_MEDIA" -i "$SUBTITLE_OUTPUT" -c copy -c:s copy "$OUTPUT_VIDEO"
    else
        ffmpeg -y -i "$INPUT_MEDIA" -i "$SUBTITLE_OUTPUT" -c copy -c:s "$SRT_CODEC" "$OUTPUT_VIDEO"
    fi
}

# Finalize output by moving files to the output directory
finalize_output() {
    if [ "$IS_VIDEO" = "video" ]; then
        # Move the final output video file from cache to output directory
        cp "$OUTPUT_VIDEO" "$OUT_DIR/"
        # Also move the SRT to the output directory for reference
        cp "$SUBTITLE_OUTPUT" "$OUT_DIR/${BASENAME}.srt"
        echo "Done! Final video with subtitles: $OUT_DIR/${BASENAME}_with_subs.${INPUT_EXT}"
        echo "Subtitles file: $OUT_DIR/${BASENAME}.srt"
    else
        # For audio-only, move the SRT file to the output directory
        mv "$SUBTITLE_OUTPUT" "$OUT_DIR/${BASENAME}.srt"
        echo "Done! Lyrics subtitles file:"
        echo "SRT: $OUT_DIR/${BASENAME}.srt"
    fi
}

# Show parameters to the user
echo "Parameters:"
echo "  Input Media    : $INPUT_MEDIA"
echo "  SHA1           : $SHA1"
echo "  Whisper Model  : $MODEL"
if [ "$IS_VIDEO" = "video" ]; then
    echo "  Detected Type  : Video"
    echo "  Output Video   : $OUTPUT_VIDEO"
    echo "  SRT Codec      : $SRT_CODEC"
else
    echo "  Detected Type  : Audio"
    echo "  Sub Output     : SRT"
fi

# Main process
initialize_directories
run_spleeter
run_subsai

if [ "$IS_VIDEO" = "video" ]; then
    merge_subtitles_video
fi

finalize_output
