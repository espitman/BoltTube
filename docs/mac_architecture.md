# BoltTube Mac Native - YouTube Download Architecture

## 1. Overview
BoltTube Mac Native uses a hybrid Swift + Python architecture for YouTube import and local media serving.

The important distinction is:
- The macOS app UI is written in SwiftUI.
- The YouTube extraction and download logic runs in Python.
- Swift does not resolve YouTube streams directly.
- Swift orchestrates Python subprocesses and a local HTTP bridge.

This document describes the real download structure used by the current codebase, with a focus on YouTube import, metadata resolution, download execution, progress propagation, persistence, and local playback.

## 2. Main Runtime Pieces

### 2.1 SwiftUI App Layer
The Swift app is the user-facing layer.

Primary file:
[ServerController.swift](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/ServerController.swift)

Responsibilities:
- Holds UI state such as `videoURL`, `resolvedTitle`, `formats`, `selectedFormatID`, `isResolvingQualities`, `isDownloading`, and `libraryItems`.
- Starts and stops the Python bridge server.
- Runs Python CLI commands for resolve, list, and download.
- Consumes JSON output from Python.
- Consumes progress events from Python stderr during downloads.
- Updates the SwiftUI screen.

### 2.2 SwiftUI View Layer
The import UI is declared in:
[ContentView.swift](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/ContentView.swift)

Relevant UI entry points:
- URL input field bound to `controller.videoURL`
- `Paste` button
- automatic metadata refresh on URL change
- quality pills
- download button
- progress bar

Key triggers:
- `onChange(of: controller.videoURL)` calls `scheduleQualityRefresh()`
- pressing Enter in the text field calls `scheduleQualityRefresh()`
- the download button calls `downloadVideo()`

### 2.3 Python Bridge Layer
The Python media bridge is:
[bridge_server.py](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/Resources/bridge_server.py)

Responsibilities:
- Exposes local HTTP endpoints for library, playlists, channels, resolve, download, delete, and metadata refresh.
- Exposes CLI commands that Swift calls directly.
- Uses `pytubefix` to talk to YouTube.
- Selects a stable `pytubefix` client for problematic videos.
- Downloads progressive or adaptive streams.
- Merges video and audio with `ffmpeg` when needed.
- Emits progress JSON on stderr during downloads.

### 2.4 Library / Persistence Layer
Media persistence is implemented in:
- [library.py](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/Resources/library.py)
- [repository.py](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/Resources/repository.py)

Responsibilities:
- Owns the download directory.
- Stores media records in SQLite, not in the old JSON manifest flow.
- Persists metadata such as title, thumbnail, duration, source URL, stream URL, and file path.
- Supports playlists, channels, and metadata refresh.

## 3. The End-to-End YouTube Flow

### 3.1 User enters or pastes a URL
Entry point:
[ContentView.swift](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/ContentView.swift)

Flow:
1. The user pastes a YouTube URL.
2. The value is written into `ServerController.videoURL`.
3. `scheduleQualityRefresh()` is triggered.

Relevant controller method:
[ServerController.swift](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/ServerController.swift)

What `scheduleQualityRefresh()` does:
- Cancels the previous pending metadata task.
- Trims the current URL.
- Clears state if the field is empty.
- Waits about 600ms before firing resolve.

This debounce is important because the UI updates on every keystroke and we do not want to spawn Python resolve jobs for partial URLs.

### 3.2 Swift resolves metadata and formats
The real resolve path is:
- Swift calls `resolveQualities(for:)`
- `resolveQualities(for:)` runs Python with the CLI command:
  `bridge_server.py resolve --download-dir <dir> --url <url>`

Relevant method:
[ServerController.swift](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/ServerController.swift)

Execution details:
- `ensurePythonReady()` ensures the venv exists.
- `runJSONCommand(...)` launches Python via `Process`.
- stdout is expected to contain one valid JSON payload.
- stderr is captured separately.
- if the Python process exits non-zero, Swift throws and logs `Quality load failed.`

### 3.3 Python picks a safe `pytubefix` client
This is one of the most important parts of the current design.

Relevant functions:
[bridge_server.py](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/Resources/bridge_server.py)

Functions:
- `_choose_client(url)`
- `_probe_client_worker(url, client, result_queue)`

Why this exists:
- Some YouTube videos hang or fail depending on which `pytubefix` client is used.
- The current bridge does not assume one client always works.
- It tries a short list of clients:
  `WEB`, `IOS`, `TV`, `ANDROID_VR`
- Each candidate is probed in a separate process with a timeout.

What this protects against:
- Infinite skeleton loading in the UI
- one bad client freezing the whole resolve path
- a single stuck `YouTube(...)` instance blocking the main bridge command forever

Important implementation detail:
- The probe runs in a child process.
- If the child hangs, it is terminated after `CLIENT_PROBE_TIMEOUT`.
- The bridge then tries the next candidate.

### 3.4 Python builds the resolve payload
After a client is selected, the bridge calls:
- `_build_resolve_payload(url, client)`

This function:
1. Instantiates `YouTube(url, client=...)`
2. Resolves title
3. Resolves thumbnail via `_stable_t(...)`
4. Reads duration
5. Enumerates MP4 streams
6. Computes size for progressive streams directly
7. Computes estimated merged size for adaptive streams using best matching MP4 audio

The resolve payload returned to Swift looks like:
- `title`
- `thumbnailUrl`
- `durationSeconds`
- `formats`

Each format contains:
- `id`
- `title`
- `details`
- `filesize`

Current meaning of format details:
- `single file`
  progressive stream, no merge required
- `video+audio merge`
  adaptive stream, ffmpeg merge required

### 3.5 Swift updates the preview UI
Once Swift decodes the resolve JSON into `ResolveResponse`, it updates:
- `resolvedTitle`
- `resolvedThumbnailUrl`
- `resolvedDurationSeconds`
- `formats`
- `selectedFormatID`

This drives:
- thumbnail preview
- title preview
- duration badge
- quality chips
- enabled/disabled state of the download button

## 4. The Actual Download Flow

### 4.1 User presses Download
Entry point:
[ContentView.swift](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/ContentView.swift)

Button action:
- `Task { await controller.downloadVideo() }`

### 4.2 Swift launches the Python download command
Relevant method:
[ServerController.swift](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/ServerController.swift)

The command is:
`bridge_server.py download-progress --download-dir <dir> --url <url> --format-id <selectedFormatID>`

This is not an HTTP request.
The macOS app uses a direct Python subprocess for the actual download because it needs streaming progress events from stderr.

This is an important architectural split:
- metadata resolve: direct Python CLI
- actual download with progress: direct Python CLI
- local browsing / playlists / channels / media serving: local HTTP bridge

### 4.3 Swift listens to stderr for progress
`runDownloadCommand(...)` launches Python and attaches:
- stdout pipe
- stderr pipe

Progress protocol:
- Python prints JSON progress events on stderr
- Swift reads stderr incrementally
- each full line is parsed as JSON
- `handleDownloadProgressLine(...)` updates UI state

Supported events currently emitted by Python:
- `starting`
- `progress`
- `merging`

Current Swift reactions:
- `starting`
  saves temporary file prefix for later cleanup
- `progress`
  updates progress fraction and progress label
- `merging`
  changes label to merging state

### 4.4 Python downloads the stream with `pytubefix`
Relevant function:
[bridge_server.py](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/Resources/bridge_server.py)

Function:
- `_download_with_progress(url, format_id, client)`

Steps:
1. Create `YouTube(url, client=chosen_client)`
2. Resolve the selected stream by itag
3. Resolve best audio stream if the selected stream is adaptive
4. Calculate `total_bytes`
5. Register `on_progress_callback`
6. Emit `starting` event to stderr
7. Download progressive or adaptive stream(s)
8. If adaptive, merge with `ffmpeg`
9. Add final file to the media library
10. Return JSON with `id`, `streamUrl`, `fileName`

### 4.5 Progressive vs adaptive behavior

#### Progressive stream
Characteristics:
- single `.mp4`
- contains video and audio together
- no merge step

Path:
- `stream.is_progressive == True`
- downloaded directly to `<tempName>.mp4`

#### Adaptive stream
Characteristics:
- separate video-only stream
- separate audio-only stream
- requires local merge

Path:
- video is downloaded to a temporary `.v`
- audio is downloaded to a temporary `.a`
- bridge emits `merging`
- `ffmpeg` is executed with:
  `-c:v copy`
  `-c:a aac`
  `-movflags +faststart`
- temporary `.v` and `.a` files are removed

This preserves higher quality while still producing a final `.mp4` file suitable for local playback.

## 5. Library Persistence

### 5.1 Final file registration
Once Python has a finished media file, it calls:
- `library.add(...)`

Relevant file:
[library.py](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/Resources/library.py)

What `add(...)` does:
- creates a final media ID by appending a short UUID suffix
- renames the file to match that ID
- creates a stable `/media/<id>` stream URL
- stores source URL
- stores thumbnail URL
- stores duration
- stores title
- writes a row to SQLite

### 5.2 SQLite is the source of truth
The current system uses SQLite through `MediaRepository`.

Relevant file:
[repository.py](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/Resources/repository.py)

Stored media fields include:
- `id`
- `file_name`
- `file_path`
- `stream_url`
- `size`
- `created_at`
- `source_url`
- `thumbnail_url`
- `duration`
- `title`

This is also the metadata source for:
- library grid
- playlists
- channels
- metadata refresh

### 5.3 Metadata backfill and refresh
If metadata is incomplete, the system has two backfill paths.

#### File reprobe
`library.py` can re-read media metadata via ffprobe for:
- duration
- embedded title if present

#### Source refresh
`refresh_metadata(media_id)` re-fetches metadata from YouTube using `pytubefix` and updates:
- `title`
- `thumbnail_url`
- `duration`

This is what the UI uses for "Refresh Metadata".

## 6. Local HTTP Bridge Responsibilities

The Python script is also a local Flask server started by Swift via:
`bridge_server.py serve --port <port> --download-dir <dir>`

Relevant method:
[ServerController.swift](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/ServerController.swift)

HTTP endpoints currently relevant to download architecture:
- `GET /health`
- `GET /api/items`
- `GET /media/<media_id>`
- `POST /api/resolve`
- `POST /api/download`
- `POST /api/delete`
- `POST /api/refresh-metadata`

Even though Swift currently prefers direct CLI for resolve/download, these HTTP endpoints still matter because:
- the app uses HTTP for browsing and media serving
- the architecture supports local REST access
- playlists and channels are all served over the same local bridge

## 7. Process Model

There are two distinct Python execution modes in this app.

### 7.1 Long-running bridge server
Started by:
- `startShareServer()`

Purpose:
- serve local media
- serve library APIs
- serve playlist/channel APIs
- expose local control endpoints

### 7.2 Short-lived worker subprocesses
Started by:
- `runJSONCommand(...)`
- `runDownloadCommand(...)`

Purpose:
- isolate resolve work
- isolate download work
- avoid coupling progress streaming to the HTTP request lifecycle
- keep the UI responsive

This split is intentional. Download execution is treated as a job, not just a REST call.

## 8. Error and Recovery Model

### 8.1 Resolve failures
If resolve fails:
- Swift logs `Quality load failed.`
- `isResolvingQualities` returns to `false`
- the user remains on the import screen

Current causes can include:
- unsupported YouTube response shape
- a `pytubefix` client hanging
- no client succeeding in `_choose_client`
- malformed URL

### 8.2 Download failures
If download fails:
- Swift logs `Download failed: ...`
- download UI resets out of active progress mode

### 8.3 User cancellation
`cancelDownload()`:
- terminates the active Python process
- kills child processes spawned under it
- removes partial temp files by prefix
- resets progress state

This avoids leaving half-downloaded `.v`, `.a`, or `.mp4` files behind.

## 9. Why This Architecture Exists

This design solves several concrete problems:

- SwiftUI is good at UI orchestration, not at YouTube extraction.
- `pytubefix` is specialized for YouTube extraction and stream selection.
- `ffmpeg` is the right tool for merging adaptive media.
- a direct subprocess is simpler for real-time progress than trying to stream progress over REST into Swift.
- keeping the heavy media logic in Python reduces Swift-side protocol complexity.
- isolating extraction logic in a worker process makes hangs and crashes less damaging to the UI.

## 10. Files To Read Together

For the full import/download pipeline, these are the core files:

1. [ContentView.swift](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/ContentView.swift)
2. [ServerController.swift](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/ServerController.swift)
3. [bridge_server.py](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/Resources/bridge_server.py)
4. [library.py](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/Resources/library.py)
5. [repository.py](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/Sources/BoltTubeMacNative/Resources/repository.py)

## 11. Current Reality vs Old Assumptions

A few older architectural assumptions are no longer true:

- The bridge is no longer just a simple BaseHTTPRequestHandler server; it is now Flask-based.
- SQLite is the current persistence layer for media metadata.
- The app does not rely only on HTTP for import operations; direct Python CLI subprocesses are central to resolve and download.
- The system now contains playlist and channel features, so the bridge is broader than a pure downloader.
- `pytubefix` client selection is part of the actual runtime design and not an implementation detail.

---
Document version: 2.0.0
Updated: April 2026
