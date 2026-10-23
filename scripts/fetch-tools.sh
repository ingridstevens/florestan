#!/bin/zsh
# Downloads the standalone tools Florestan carries inside its app bundle, so it runs on a Mac without Homebrew:
#   yt-dlp  – official universal build (github.com/yt-dlp/yt-dlp), the unpacked `yt-dlp_macos.zip` one: the
#             single-file `yt-dlp_macos` unpacks itself into a new temporary folder on every run, and macOS
#             checks those fresh files each time, which adds about 20 seconds to every song. Florestan updates it.
#   deno    – JavaScript runtime yt-dlp needs for YouTube (github.com/denoland/deno)
#   ffmpeg, ffprobe – static Apple Silicon builds by Martin Riedl (ffmpeg.martin-riedl.de)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=Support/Tools
mkdir -p "$OUT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading yt-dlp…"
YTDLP_RELEASE=https://github.com/yt-dlp/yt-dlp/releases/latest/download
curl -fsSL -o "$TMP/yt-dlp_macos.zip" "$YTDLP_RELEASE/yt-dlp_macos.zip"
curl -fsSL -o "$TMP/SHA2-256SUMS" "$YTDLP_RELEASE/SHA2-256SUMS"
(cd "$TMP" && grep ' yt-dlp_macos.zip$' SHA2-256SUMS | shasum -a 256 -c -)
rm -rf "$OUT/yt-dlp" "$OUT/yt-dlp_macos"
ditto -x -k "$TMP/yt-dlp_macos.zip" "$OUT/yt-dlp_macos"
echo "Downloading deno…"
curl -fsSL -o "$TMP/deno.zip" https://github.com/denoland/deno/releases/latest/download/deno-aarch64-apple-darwin.zip
unzip -oq "$TMP/deno.zip" -d "$OUT"
for tool in ffmpeg ffprobe; do
    echo "Downloading $tool…"
    curl -fsSL -o "$TMP/$tool.zip" "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/$tool.zip"
    unzip -oq "$TMP/$tool.zip" -d "$OUT"
done
chmod +x "$OUT"/deno "$OUT"/ffmpeg "$OUT"/ffprobe "$OUT"/yt-dlp_macos/yt-dlp_macos
/usr/bin/xattr -cr "$OUT"

# Florestan compares this with its installed copies to know when to refresh them.
{
    echo "yt-dlp=$("$OUT/yt-dlp_macos/yt-dlp_macos" --version)"
    echo "deno=$("$OUT/deno" --version | head -1 | cut -d' ' -f2)"
    echo "ffmpeg=$("$OUT/ffmpeg" -version | head -1 | cut -d' ' -f3)"
} > "$OUT/VERSIONS"
cat "$OUT/VERSIONS"
