#!/bin/zsh
# Builds Florestan.exe.app (no Xcode needed) and installs it into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Florestan.exe.app"
swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Florestan" "$APP/Contents/MacOS/Florestan"
cp Support/Info.plist "$APP/Contents/Info.plist"

if [[ ! -f build/AppIcon.icns ]]; then
    swift scripts/make-icon.swift build
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with the local certificate if it's set up (./scripts/setup-signing.sh), so macOS keeps Florestan's
# permissions across builds. Otherwise sign ad hoc, which notifications and the Music prompt still need.
IDENTITY="Florestan Local Signing"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "Signing ad hoc; run ./scripts/setup-signing.sh once so permissions survive rebuilds."
    codesign --force --sign - "$APP"
fi

if [[ "${1:-}" != "--no-install" ]]; then
    mkdir -p ~/Applications
    pkill -x Florestan 2>/dev/null || true
    rm -rf ~/Applications/Florestan.exe.app
    cp -R "$APP" ~/Applications/
    echo "Installed to ~/Applications/Florestan.exe.app"
fi
