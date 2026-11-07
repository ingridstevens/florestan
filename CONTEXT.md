# Florestan.exe

A personal Mac app that turns YouTube and YouTube Music links into songs in the owner's Apple Music library, so they can be played later from Apple Music, or from Florestan's menu bar panel, which remote-controls the Music app.

## Language

### Input

**Link**:
A YouTube or YouTube Music URL the user hands to Florestan, by pasting, via the menu bar panel, or via the global shortcut.
_Avoid_: URL, request

**Song Link**:
A Link that points at a single video and names no real playlist. A video inside an endless "Mix" radio is still a Song Link.
_Avoid_: video link, single

**Playlist Link**:
A Link that names a playlist or YouTube Music album, even when it also points at one video in it.
_Avoid_: list, album link

### Work

**Job**:
The work of processing one Link from start to finish. Jobs wait in the Queue and run one at a time.
_Avoid_: task, download

**Queue**:
The ordered line of Jobs waiting to run. It's saved as Links are added, so Jobs left running or waiting when Florestan quits carry on at the next launch.

**Another Copy**:
A different upload of the same song by the same artist, found on YouTube Music when YouTube won't play a Track's video where the user is. Only looked for when the user turns it on; the Ledger still records the Track under its original video.
_Avoid_: alternative, mirror, fallback in UI copy

**Track**:
One song within a Job, from fetching the audio through appearing in Apple Music. A Song Link's Job has one Track; a Playlist Link's Job has one per playlist entry.
_Avoid_: item, entry, file

### Result

**Import**:
The moment a Track becomes a song in the Apple Music library.
_Avoid_: add, sync

**Mirrored Playlist**:
The Apple Music playlist Florestan creates for a Playlist Link, with the same name and order as on YouTube.
_Avoid_: copied playlist

**Ledger**:
Florestan's record of every YouTube video it has already imported. A Track already in the Ledger is skipped.
_Avoid_: history, cache, database

**Tidy Albums**:
Putting Imported songs from plain YouTube videos onto their real album, in album order, and making each album's songs agree on Album Artist, year and a square cover, so Apple Music shows the album once.
_Avoid_: fix, clean up, organize

**Recommendation**:
A YouTube song Florestan proposes because YouTube relates it to songs already imported. Added or turned down one at a time.
_Avoid_: suggestion (that word belongs to Eusebius), discovery

**Idea**:
A song Apple Intelligence proposes on this Mac, without going online. Only an artist and title until the user adds it, at which point Florestan looks it up on YouTube.
_Avoid_: offline recommendation, AI pick

### Playing

**Now Playing**:
What the Music app is playing, shown with its controls in the menu bar panel. Florestan only sends Music commands; it never plays audio itself, and never opens Music to show this.
_Avoid_: player (for the app's own audio), current song

**Album Artist**:
The one artist all songs of an album share in Apple Music, so they show as one album instead of separate singles, even when each song credits different performers.
_Avoid_: primary artist

### Eusebius

**Eusebius**:
Florestan's calm other half: the part of the app that looks after the whole Apple Music library after songs arrive, rather than fetching new ones.
_Avoid_: curator, organizer

**Mood**:
How a song feels to listen to (such as Focus, Late Night, Wind Down), as opposed to its genre.
_Avoid_: vibe, category, genre

**Mood Playlist**:
A playlist of one Mood, drawn from the whole library. Eusebius suggests it; it exists in Apple Music only once the user keeps it.
_Avoid_: smart playlist, auto playlist

**Kept** / **Turned down**:
The user's verdict on a suggested Mood Playlist. A kept one is created in Apple Music and updated on every run; a turned-down one is never suggested again unless the user asks.
_Avoid_: liked/disliked in UI copy, favorite, rejected
