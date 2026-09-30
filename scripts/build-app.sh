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

# Ad-hoc signature: required for notifications and the Music permission prompt.
codesign --force --sign - "$APP"

if [[ "${1:-}" != "--no-install" ]]; then
    mkdir -p ~/Applications
    pkill -x Florestan 2>/dev/null || true
    rm -rf ~/Applications/Florestan.exe.app
    cp -R "$APP" ~/Applications/
    echo "Installed to ~/Applications/Florestan.exe.app"
fi
