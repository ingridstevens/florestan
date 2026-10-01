#!/bin/zsh
# Builds a disk image to install Florestan.exe on another Mac: the app (with its own tools),
# a shortcut to Applications to drag it onto, a Read Me, and the bundled tools' licence notices.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f Support/Tools/VERSIONS ]] || ./scripts/fetch-tools.sh
./scripts/build-app.sh --no-install

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "build/Florestan.exe.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp Support/ReadMeFirst.txt "$STAGE/Read Me First.txt"
cp THIRD-PARTY-NOTICES.md "$STAGE/Third-Party Notices.md"

DMG="build/Florestan.exe.dmg"
rm -f "$DMG"
hdiutil create -volname "Florestan.exe" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
