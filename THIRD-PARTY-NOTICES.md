# Third-party software

The Florestan.exe app bundle (and the `.dmg` built by `scripts/make-dmg.sh`) carries these programs, unmodified, in
`Florestan.exe.app/Contents/Resources/Tools`. Florestan runs them as separate programs; they are not part of
Florestan's own code and keep their own licences. `scripts/fetch-tools.sh` shows exactly where each one comes from.

## yt-dlp

- Project: https://github.com/yt-dlp/yt-dlp
- Licence: The Unlicense (public domain)
- Binary: the official `yt-dlp_macos` release build

## deno

- Project: https://github.com/denoland/deno
- Licence: MIT, Copyright 2018-2026 the Deno authors
- Binary: the official `deno-aarch64-apple-darwin` release build

## FFmpeg (ffmpeg, ffprobe)

- Project: https://ffmpeg.org
- Licence: GNU General Public License, version 3 (this build is configured with `--enable-gpl --enable-version3`).
  Full text: https://www.gnu.org/licenses/gpl-3.0.html
- Binary: static Apple Silicon release builds by Martin Riedl, https://ffmpeg.martin-riedl.de
- Source code: the FFmpeg source for each release is at https://ffmpeg.org/releases/, and the scripts and
  configuration used for these builds are at https://git.martin-riedl.de/ffmpeg/build-script. Run
  `ffmpeg -version` inside the app bundle to see the exact version and configuration of the copy you have.
