#!/bin/zsh
# Saves the README's screenshots to docs/screenshots. Florestan runs on the demo state in docs/demo (see its README)
# in a temporary folder, so your own history, imports and downloads aren't shown or touched.
set -euo pipefail
cd "$(dirname "$0")/.."

DEMO=$(mktemp -d)
trap 'rm -rf "$DEMO"' EXIT
mkdir -p "$DEMO/Support/bin"
cp docs/demo/history.json docs/demo/ledger.json "$DEMO/Support/"
# Fresh suggestions, so For you shows these instead of fetching new ones.
sed "s/LAST_REFRESH/$(date -u +%Y-%m-%dT%H:%M:%SZ)/" docs/demo/recommendations.json > "$DEMO/Support/recommendations.json"
# Made-up cover art, which Florestan shows in place of YouTube thumbnails.
swift scripts/make-demo-thumbnails.swift docs/demo "$DEMO/Thumbnails"
# The bundled tools, if fetched, so the panel doesn't ask for them.
if [[ -f Support/Tools/VERSIONS ]]; then
    ln -s "$PWD/Support/Tools/yt-dlp_macos/yt-dlp_macos" "$DEMO/Support/bin/yt-dlp"
    ln -s "$PWD/Support/Tools/ffmpeg" "$DEMO/Support/bin/ffmpeg"
fi

swift build -c release
mkdir -p docs/screenshots
FLORESTAN_HOME="$DEMO" "$(swift build -c release --show-bin-path)/Florestan" --snapshot "$PWD/docs/screenshots"
ls -1 docs/screenshots
