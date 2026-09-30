# Florestan.exe

Paste a YouTube or YouTube Music link; the song (or the whole playlist) lands in Apple Music, with a matching playlist.
Eusebius, its calm other half, sorts your whole library into mood playlists using Apple's on-device model.

## Build

Needs only the Xcode Command Line Tools and Homebrew:

```sh
brew install yt-dlp ffmpeg
./scripts/build-app.sh        # builds and installs ~/Applications/Florestan.exe.app
swift test --scratch-path .build-test   # core logic tests (separate folder avoids a stale-cache bug)
```

## Use

- Menu bar icon → paste a link (a YouTube link on your clipboard is filled in automatically).
- Or copy a link anywhere and press **⌥⌘Y**.
- The window (from the menu bar panel) shows history, imported songs, Eusebius and settings.

Notes:
- The first import asks for permission to control Music.
- Rebuilding changes the app's ad-hoc signature, so macOS may ask for permissions again.
- If YouTube shows a bot check, your network is blocked (VPNs and data-center IPs often are). Switch networks or turn on "Use my YouTube login" in Settings.
- Eusebius needs Apple Intelligence turned on.

See `CONTEXT.md` for the vocabulary used in the code.
