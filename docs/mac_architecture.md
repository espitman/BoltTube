# BoltTube Mac Native - Technical Architecture

## 1. Overview
BoltTube Mac Native is built using a **Hybrid Native-Scripting Architecture**. It leverages the performance and aesthetic integration of **Swift (SwiftUI)** for the user interface and system-level operations, while delegating complex media processing and YouTube protocol handling to a **Python-based Bridge Server**.

## 2. Core Components

### 2.1 Native Swift Layer (The Orchestrator)
- **Technology Stack:** Swift 5.10+, SwiftUI, URLSession, Process (Foundation).
- **Responsibilities:**
    - **UI/UX:** Native macOS menu bar integration, progress bars, and list views.
    - **Server Management:** Lifecycle management of the Python bridge process. It ensures the server starts on app launch and kills it on exit.
    - **HTTP Client:** Communicates with the local Python bridge via RESTful APIs (localhost:9864).
    - **JSON Manifest Rendering:** Synchronously reads and displays the local library from the manifest file for immediate UI feedback.

### 2.2 Python Bridge Layer (The Engine)
- **Technology Stack:** Python 3.9+, HTTP Server (BaseHTTPRequestHandler), Threading.
- **Key Libraries:**
    - `pytubefix`: High-performance YouTube stream resolution and download.
    - `ffmpeg`: External binary for high-quality (v1080p+) stream merging.
- **Responsibilities:**
    - **Resolution API:** Resolves various stream qualities (Adaptive/Progressive) for a given URL.
    - **Download with Progress:** Handles multi-stream downloads (Video + Audio) and pipes progress events back to real-time logs.
    - **FFmpeg Merging:** Automatically merges Adaptive video files with AAC audio tracks using `ffmpeg` with `-movflags +faststart` for web-optimized playback.
    - **Metadata Sync:** Responsible for pinning High-Quality thumbnails and normalizing Persian/Unicode filenames during the download process.

## 3. Communication Protocol
The app uses two communication channels:

1. **REST API (Primary):** Swift sends POST/GET requests to the Python server for specific actions (Resolve, Download, Delete).
2. **Subprocess Pipe (Secondary):** Used for real-time progress. Swift monitors the standard error (stderr) of the Python process during downloads to parse JSON-formatted progress events.

## 4. State Management & Consistency
- **Source of Truth:** A hidden manifest file `.bolttube-library.json` located in the user's storage directory.
- **Synchronization Logic:**
    - The server performs a `_sync_disk` operation on startup to reconcile the physical file system with the manifest metadata.
    - **Unicode Normalization:** Uses NFD normalization (MacOS Standard) to ensure Persian titles match between the disk and the library.
- **Concurrency:** Implements thread-safe locking in Python to prevent manifest corruption during simultaneous download/delete operations.

## 5. Security & Isolation
- **Process Isolation:** The bridge server runs as a separate process, ensuring that any crash in the media engine doesn't bring down the main UI.
- **Sandboxing:** Operationally restricted to the `~/Movies/BoltTubeNative` directory for all file-system mutations.

## 6. Distribution Strategy (Portable Packaging)
For Standalone distribution:
1. **Embedded Python:** A portable Python environment and all required dependencies (`pytubefix`) are bundled inside the `.app/Contents/Resources`.
2. **FFmpeg Bundling:** Static `ffmpeg` binaries are included to remove any external system dependency from the user's machine.

---
*Document Version: 1.0.0*
*Created: April 2026*
