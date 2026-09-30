#!/bin/zsh
# Downloads the standalone tools Florestan carries inside its app bundle, so it runs on a Mac without Homebrew:
#   yt-dlp  – official universal build (github.com/yt-dlp/yt-dlp), keeps itself up to date with -U
#   deno    – JavaScript runtime yt-dlp needs for YouTube (github.com/denoland/deno)
#   ffmpeg, ffprobe – static Apple Silicon builds by Martin Riedl (ffmpeg.martin-riedl.de)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=Support/Tools
mkdir -p "$OUT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading yt-dlp…"
curl -fsSL -o "$OUT/yt-dlp" https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos
echo "Downloading deno…"
curl -fsSL -o "$TMP/deno.zip" https://github.com/denoland/deno/releases/latest/download/deno-aarch64-apple-darwin.zip
unzip -oq "$TMP/deno.zip" -d "$OUT"
for tool in ffmpeg ffprobe; do
    echo "Downloading $tool…"
    curl -fsSL -o "$TMP/$tool.zip" "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/$tool.zip"
    unzip -oq "$TMP/$tool.zip" -d "$OUT"
done
chmod +x "$OUT"/*
xattr -cr "$OUT"

# Florestan compares this with its installed copies to know when to refresh them.
{
    echo "yt-dlp=$("$OUT/yt-dlp" --version)"
    echo "deno=$("$OUT/deno" --version | head -1 | cut -d' ' -f2)"
    echo "ffmpeg=$("$OUT/ffmpeg" -version | head -1 | cut -d' ' -f3)"
} > "$OUT/VERSIONS"
cat "$OUT/VERSIONS"
