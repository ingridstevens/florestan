# Florestan.exe

Paste a YouTube or YouTube Music link; the song (or the whole playlist) lands in Apple Music, with a matching playlist.
Eusebius, its calm other half, sorts your whole library into mood playlists using Apple's on-device model.

## Build

Needs only the Xcode Command Line Tools:

```sh
./scripts/fetch-tools.sh      # once: downloads yt-dlp, deno and ffmpeg to carry inside the app
./scripts/build-app.sh        # builds and installs ~/Applications/Florestan.exe.app
./scripts/test.sh             # core logic tests
./scripts/setup-signing.sh    # once: a local signing certificate, so permissions survive rebuilds
```

## Install on another Mac

```sh
./scripts/make-dmg.sh         # creates build/Florestan.exe.dmg
```

Copy the `.dmg` over (AirDrop works), open it, and drag Florestan.exe into Applications. `Read Me First.txt`
inside explains the one-time "Open Anyway" step: the app isn't notarized by Apple, so macOS asks once.
Requires Apple Silicon and macOS 26. Homebrew isn't needed; the app brings its own tools and keeps yt-dlp updated.

## Use

- Menu bar icon → paste a link (a YouTube link on your clipboard is filled in automatically).
- Or copy a link anywhere and press **⌥⌘Y**.
- The window (from the menu bar panel) shows history, imported songs, Eusebius and settings.

Notes:
- The first import asks for permission to control Music.
- If YouTube shows a bot check, your network is blocked (VPNs and data-center IPs often are). Switch networks or turn on "Use my YouTube login" in Settings.
- Eusebius needs Apple Intelligence turned on.

See `CONTEXT.md` for the vocabulary used in the code.

## Your responsibility

Only download content you own or have the rights to download, such as your own uploads, or music the rights holder
has released for free download. Downloading other content may break YouTube's Terms of Service and copyright law.
You are responsible for how you use Florestan; the author accepts no liability for misuse.

## License

Public domain (the Unlicense), see `LICENSE`. Do whatever you like with it; no credit needed.
