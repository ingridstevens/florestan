# Contributing to Florestan.exe

Thanks for wanting to help. Bug reports, ideas and pull requests are all welcome. This page explains how to report
a problem, set up the project, and what makes a change easy to merge.

## What's in scope

Florestan is for music people have the rights to download (see the notice at the top of the [README](README.md)).
Changes that help it get around protections are out of scope and won't be merged: DRM, paywalls, members-only or
age-restricted videos, or anything else meant to reach content the uploader didn't make freely available.

## Reporting a problem

[Open an issue](https://github.com/ingridstevens/florestan/issues/new) and include:

- your macOS version, and Florestan's version (in **Settings › About**);
- the yt-dlp version (in **Settings › Tools**);
- what you did, what you expected, and what happened instead, with the exact error message if there was one;
- whether it was a single song, a playlist or a YouTube Music album.

There's no need to share links to anything private. A screenshot of the panel or window often says more than a
description.

## Suggesting a feature

Open an issue that describes the problem you'd like solved before you write code, so we can agree on the approach
first. Florestan tries to stay small: a menu bar app that does one job well.

## Setting up

You need a Mac with Apple Silicon, macOS 26 or later, and the Xcode Command Line Tools (`xcode-select --install`).
Xcode itself isn't needed.

```sh
git clone https://github.com/ingridstevens/florestan.git
cd florestan
./scripts/fetch-tools.sh      # yt-dlp, deno and ffmpeg to carry inside the app
./scripts/setup-signing.sh    # once: a local signing certificate, so permissions survive rebuilds
./scripts/build-app.sh        # builds and installs ~/Applications/Florestan.exe.app
./scripts/test.sh             # the tests
```

`build-app.sh` quits any running Florestan before installing the new build.

## Finding your way around

- **`Sources/FlorestanCore`**: logic with no UI and no system calls (reading links, song details, yt-dlp output,
  matching songs, tidying albums, the Ledger). Everything here is tested in `Tests/FlorestanCoreTests`.
- **`Sources/Florestan`**: the app.
  - `AppModel.swift` runs the Queue.
  - `Services/` talks to the outside world: yt-dlp (`Downloader`, `Shell`, `ToolInstaller`) and the Music app
    (`MusicLibrary`, `MusicPlayer`).
  - `UI/` holds the menu bar panel, the window's pages and the menu bar icon.
- **`CONTEXT.md`**: the words the code uses (Job, Track, Queue, Ledger, Mirrored Playlist…). Use them in code,
  comments and issues, and avoid the alternatives it lists.
- **`scripts/`**: building, testing, the disk image, screenshots and the app icon.
- **`docs/demo`**: the made-up songs the screenshots are taken from.

## Making a change

- **Put logic you can test in `FlorestanCore`**, with tests, and keep the app side thin.
- **Scripts for the Music app take values through `argv`**, never by pasting them into the script text, so a song
  title with quotes can't break it. Follow the pattern in `MusicLibrary.swift`.
- **Use `@ViewState`, not `@State`**, in views. `@State` needs a macro plugin that only ships with Xcode, so it
  doesn't build with the Command Line Tools alone (see `UI/ViewState.swift`).
- **Write text people see in plain words**, named after what they recognise ("Imported songs", not "Ledger"), and
  say how to fix an error, not only what went wrong.
- **Comments say why**, not what the next line does. Match the style of the code around your change.

## Before you open a pull request

1. Run `./scripts/test.sh`; all tests should pass.
2. Build and try your change in the real app with `./scripts/build-app.sh`.
3. If you changed what a screen looks like, run `./scripts/make-screenshots.sh` and include the updated images.
   It uses the made-up songs in `docs/demo`, never your own library.
4. Keep the pull request to one change. Describe what it does and why, and add a before-and-after screenshot for
   anything visible.

## Releases

Releases are made by the maintainer:

1. Set the version in `Support/Info.plist` (`CFBundleShortVersionString`, and bump `CFBundleVersion`) and on the
   README's version line.
2. Run `./scripts/make-dmg.sh` and check the disk image.
3. Publish a GitHub release tagged `vX.Y.Z` with `build/Florestan.exe.dmg` attached.
4. Update the Homebrew cask: see [`packaging/homebrew`](packaging/homebrew/README.md).

## Licence

Florestan's code is in the public domain under the [Unlicense](LICENSE). By contributing, you agree to release your
contribution under the same terms.
