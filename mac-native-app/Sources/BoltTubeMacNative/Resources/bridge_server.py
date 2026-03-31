#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import re
import shutil
import subprocess
import sys
import threading
import uuid
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

from pytubefix import YouTube


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def readable_size(size: int | None) -> str:
    if not size:
        return ""
    mb = size / (1024 * 1024)
    if mb >= 1024:
        return f"{mb / 1024:.2f} GB"
    return f"{mb:.1f} MB"


def sanitize_filename(value: str) -> str:
    cleaned = re.sub(r"[^\w\-. ]+", "_", value).strip()
    return cleaned[:120] or "video"


@dataclass
class MediaItem:
    id: str
    file_name: str
    file_path: str
    stream_url: str
    size: str
    created_at: str
    source_url: str
    thumbnail_url: str


class MediaLibrary:
    def __init__(self, download_dir: Path) -> None:
        self.download_dir = download_dir
        self.download_dir.mkdir(parents=True, exist_ok=True)
        self.manifest_path = self.download_dir / ".bolttube-library.json"
        self._lock = threading.Lock()
        self._items: dict[str, MediaItem] = {}
        self._load()

    def _load(self) -> None:
        if self.manifest_path.exists():
            try:
                payload = json.loads(self.manifest_path.read_text())
                for raw_item in payload.get("items", []):
                    item = MediaItem(**raw_item)
                    if Path(item.file_path).exists():
                        self._items[item.id] = item
            except Exception as error:  # noqa: BLE001
                print(f"Failed to read manifest: {error}", file=sys.stderr, flush=True)
        self._sync_disk()

    def _save(self) -> None:
        payload = {"items": [asdict(item) for item in self._items.values() if Path(item.file_path).exists()]}
        self.manifest_path.write_text(json.dumps(payload, indent=2))

    def _sync_disk(self) -> None:
        for file in self.download_dir.glob("*.mp4"):
            if any(existing.file_path == str(file) for existing in self._items.values()):
                continue
            media_id = file.stem
            created_at = datetime.fromtimestamp(file.stat().st_mtime, tz=timezone.utc).isoformat()
            self._items[media_id] = MediaItem(
                id=media_id,
                file_name=file.name,
                file_path=str(file),
                stream_url=f"/media/{media_id}",
                size=readable_size(file.stat().st_size),
                created_at=created_at,
                source_url="",
                thumbnail_url="",
            )
        self._save()

    def list_items(self) -> list[dict[str, str]]:
        with self._lock:
            self._sync_disk()
            items = sorted(self._items.values(), key=lambda item: item.created_at, reverse=True)
            return [
                {
                    "id": item.id,
                    "fileName": item.file_name,
                    "streamUrl": item.stream_url,
                    "size": item.size,
                    "createdAt": item.created_at,
                    "thumbnailUrl": item.thumbnail_url,
                }
                for item in items
            ]

    def get(self, media_id: str) -> MediaItem | None:
        with self._lock:
            self._sync_disk()
            return self._items.get(media_id)

    def add(self, *, source_url: str, file_path: Path, thumbnail_url: str = "") -> MediaItem:
        with self._lock:
            media_id = f"{file_path.stem}-{uuid.uuid4().hex[:8]}"
            final_path = file_path.with_name(f"{media_id}{file_path.suffix}")
            file_path.rename(final_path)
            item = MediaItem(
                id=media_id,
                file_name=final_path.name,
                file_path=str(final_path),
                stream_url=f"/media/{media_id}",
                size=readable_size(final_path.stat().st_size),
                created_at=now_iso(),
                source_url=source_url,
                thumbnail_url=thumbnail_url,
            )
            self._items[item.id] = item
            self._save()
            return item


class BridgeService:
    TARGET_RESOLUTIONS = ("1080p", "720p", "480p", "360p", "240p")

    def __init__(self, download_dir: Path) -> None:
        self.library = MediaLibrary(download_dir)

    def resolve(self, url: str) -> dict[str, object]:
        yt = YouTube(url)
        mp4_streams = (
            yt.streams.filter(file_extension="mp4")
            .order_by("resolution")
            .desc()
        )

        formats: list[dict[str, str]] = []
        selected_by_resolution: dict[str, object] = {}

        for stream in mp4_streams:
            resolution = stream.resolution
            if not stream.itag or resolution not in self.TARGET_RESOLUTIONS:
                continue
            if resolution in selected_by_resolution:
                continue
            selected_by_resolution[resolution] = stream

        # Build formats in ascending order (lowest first = left in UI)
        for resolution in reversed(self.TARGET_RESOLUTIONS):
            stream = selected_by_resolution.get(resolution)
            if stream is None:
                continue
            details = [
                "single file" if stream.is_progressive else "video+audio merge",
                stream.mime_type,
                readable_size(stream.filesize or stream.filesize_approx),
            ]
            formats.append(
                {
                    "id": str(stream.itag),
                    "title": resolution,
                    "details": " • ".join(part for part in details if part),
                    "filesize": readable_size(stream.filesize or stream.filesize_approx),
                }
            )

        duration_seconds = getattr(yt, "length", None) or 0
        return {
            "title": yt.title,
            "thumbnailUrl": yt.thumbnail_url or "",
            "durationSeconds": int(duration_seconds),
            "formats": formats,
        }

    def download(self, url: str, format_id: str) -> dict[str, str]:
        yt = YouTube(url)
        stream = self._find_stream(yt, format_id)

        if stream is None:
            raise ValueError("Requested format was not found")

        suggested_name = sanitize_filename(yt.title or "video")
        temp_name = f"{suggested_name}-{uuid.uuid4().hex[:8]}"
        file_path = self._download_streams(
            yt=yt,
            stream=stream,
            temp_name=temp_name,
        )

        item = self.library.add(source_url=url, file_path=file_path, thumbnail_url=yt.thumbnail_url or "")
        return {
            "id": item.id,
            "streamUrl": item.stream_url,
            "fileName": item.file_name,
        }

    def download_with_progress(self, url: str, format_id: str) -> dict[str, str]:
        progress_state: dict[str, int] = {"total": 0}

        def on_progress(stream, _chunk, bytes_remaining: int) -> None:
            total = progress_state["total"] or stream.filesize or stream.filesize_approx or 0
            progress_state["total"] = int(total or 0)
            downloaded = max(progress_state["total"] - bytes_remaining, 0)
            payload = {
                "event": "progress",
                "downloadedBytes": downloaded,
                "totalBytes": progress_state["total"],
                "fraction": (downloaded / progress_state["total"]) if progress_state["total"] else 0,
            }
            print(json.dumps(payload), file=sys.stderr, flush=True)

        yt = YouTube(url, on_progress_callback=on_progress)
        stream = self._find_stream(yt, format_id)

        if stream is None:
            raise ValueError("Requested format was not found")

        audio_stream = self._best_audio_stream(yt) if not stream.is_progressive else None
        total_bytes = int(stream.filesize or stream.filesize_approx or 0)
        if audio_stream is not None:
            total_bytes += int(audio_stream.filesize or audio_stream.filesize_approx or 0)

        suggested_name = sanitize_filename(yt.title or "video")
        temp_name = f"{suggested_name}-{uuid.uuid4().hex[:8]}"
        progress_state["total"] = total_bytes
        print(
            json.dumps(
                {
                    "event": "starting",
                    "title": yt.title,
                    "formatId": format_id,
                    "totalBytes": total_bytes,
                    "tempName": temp_name,
                }
            ),
            file=sys.stderr,
            flush=True,
        )

        file_path = self._download_streams(
            yt=yt,
            stream=stream,
            temp_name=temp_name,
            progress_callback=on_progress,
            emit_events=True,
        )
        item = self.library.add(source_url=url, file_path=file_path, thumbnail_url=yt.thumbnail_url or "")
        return {
            "id": item.id,
            "streamUrl": item.stream_url,
            "fileName": item.file_name,
        }

    def list_items(self) -> dict[str, list[dict[str, str]]]:
        return {"items": self.library.list_items()}

    def _find_stream(self, yt: YouTube, format_id: str):
        if format_id == "best":
            format_id = "1080" if self._find_stream_by_resolution(yt, "1080p") else "720"
            matched = self._find_stream_by_resolution(yt, f"{format_id}p")
            if matched is not None:
                return matched
        return yt.streams.get_by_itag(int(format_id))

    def _find_stream_by_resolution(self, yt: YouTube, resolution: str):
        streams = yt.streams.filter(file_extension="mp4").order_by("resolution").desc()
        for stream in streams:
            if stream.resolution == resolution:
                return stream
        return None

    def _best_audio_stream(self, yt: YouTube):
        return (
            yt.streams.filter(only_audio=True, subtype="mp4")
            .order_by("abr")
            .desc()
            .first()
        )

    def _download_streams(self, yt: YouTube, stream, temp_name: str, progress_callback=None, emit_events: bool = False) -> Path:
        target_dir = self.library.download_dir
        if stream.is_progressive:
            download_args = {
                "output_path": str(target_dir),
                "filename": f"{temp_name}.{stream.subtype or 'mp4'}",
            }
            if progress_callback is not None:
                yt.register_on_progress_callback(progress_callback)
            return Path(stream.download(**download_args))

        audio_stream = self._best_audio_stream(yt)
        if audio_stream is None:
            raise ValueError("No compatible audio stream found for merge")
        ffmpeg_path = shutil.which("ffmpeg")
        if not ffmpeg_path:
            raise ValueError("ffmpeg is required for high-quality downloads but was not found")

        if progress_callback is not None:
            yt.register_on_progress_callback(progress_callback)

        video_path = Path(
            stream.download(
                output_path=str(target_dir),
                filename=f"{temp_name}.video.{stream.subtype or 'mp4'}",
                skip_existing=False,
            )
        )
        audio_path = Path(
            audio_stream.download(
                output_path=str(target_dir),
                filename=f"{temp_name}.audio.{audio_stream.subtype or 'mp4'}",
                skip_existing=False,
            )
        )
        final_path = target_dir / f"{temp_name}.mp4"
        if emit_events:
            print(json.dumps({"event": "merging"}), file=sys.stderr, flush=True)
        try:
            self._merge_streams(ffmpeg_path, video_path, audio_path, final_path)
            return final_path
        finally:
            video_path.unlink(missing_ok=True)
            audio_path.unlink(missing_ok=True)

    def _merge_streams(self, ffmpeg_path: str, video_path: Path, audio_path: Path, final_path: Path) -> None:
        command = [
            ffmpeg_path,
            "-nostdin",
            "-y",
            "-i", str(video_path),
            "-i", str(audio_path),
            "-c:v", "copy",
            "-c:a", "aac",
            "-movflags", "+faststart",
            str(final_path),
        ]
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            stdin=subprocess.DEVNULL,
        )
        if completed.returncode != 0:
            raise ValueError(completed.stderr.strip() or "ffmpeg merge failed")


class RequestHandler(BaseHTTPRequestHandler):
    service: BridgeService
    server_version = "BoltTubeShare/1.0"

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(HTTPStatus.NO_CONTENT)
        self._send_cors_headers()
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        self._handle_request(include_body=True)

    def do_HEAD(self) -> None:  # noqa: N802
        self._handle_request(include_body=False)

    def _handle_request(self, *, include_body: bool) -> None:
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/":
            self.send_response(HTTPStatus.OK)
            self._send_cors_headers()
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"BoltTube Bridge Server is running! Use /health or /api/items for details.")
            return

        if path == "/health":
            self._send_json(
                {
                    "status": "ok",
                    "port": self.server.server_address[1],
                    "downloadDir": str(self.service.library.download_dir),
                },
                include_body=include_body,
            )
            return

        if path == "/api/items":
            self._send_json(self.service.list_items(), include_body=include_body)
            return

        if path.startswith("/media/"):
            media_id = unquote(path.removeprefix("/media/"))
            item = self.service.library.get(media_id)
            if item is None or not Path(item.file_path).exists():
                self._send_json({"error": "Media not found"}, status=HTTPStatus.NOT_FOUND, include_body=include_body)
                return
            self._send_file(Path(item.file_path), include_body=include_body)
            return

        self._send_json({"error": "Not found"}, status=HTTPStatus.NOT_FOUND, include_body=include_body)

    def log_message(self, format: str, *args: object) -> None:
        print(f"[HTTP] {self.address_string()} - {format % args}", flush=True)

    def _send_json(
        self,
        payload: dict[str, object],
        status: HTTPStatus = HTTPStatus.OK,
        *,
        include_body: bool = True,
    ) -> None:
        data = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self._send_cors_headers()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if include_body:
            self.wfile.write(data)

    def _send_file(self, path: Path, *, include_body: bool = True) -> None:
        data = path.read_bytes()
        mime_type, _ = mimetypes.guess_type(path.name)
        self.send_response(HTTPStatus.OK)
        self._send_cors_headers()
        self.send_header("Content-Type", mime_type or "application/octet-stream")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if include_body:
            self.wfile.write(data)

    def _send_cors_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS")


def add_download_dir_argument(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--download-dir", type=Path, required=True)


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="BoltTube local downloader and share server powered by pytubefix")
    subparsers = parser.add_subparsers(dest="command", required=True)

    resolve_parser = subparsers.add_parser("resolve")
    add_download_dir_argument(resolve_parser)
    resolve_parser.add_argument("--url", required=True)

    download_parser = subparsers.add_parser("download")
    add_download_dir_argument(download_parser)
    download_parser.add_argument("--url", required=True)
    download_parser.add_argument("--format-id", required=True)

    download_progress_parser = subparsers.add_parser("download-progress")
    add_download_dir_argument(download_progress_parser)
    download_progress_parser.add_argument("--url", required=True)
    download_progress_parser.add_argument("--format-id", required=True)

    list_parser = subparsers.add_parser("list")
    add_download_dir_argument(list_parser)

    serve_parser = subparsers.add_parser("serve")
    add_download_dir_argument(serve_parser)
    serve_parser.add_argument("--port", type=int, default=9864)

    return parser


def run_command(args: argparse.Namespace) -> int:
    service = BridgeService(args.download_dir)

    if args.command == "resolve":
        print(json.dumps(service.resolve(args.url)), flush=True)
        return 0

    if args.command == "download":
        print(json.dumps(service.download(args.url, args.format_id)), flush=True)
        return 0

    if args.command == "download-progress":
        print(json.dumps(service.download_with_progress(args.url, args.format_id)), flush=True)
        return 0

    if args.command == "list":
        print(json.dumps(service.list_items()), flush=True)
        return 0

    if args.command == "serve":
        RequestHandler.service = service
        with ThreadingHTTPServer(("0.0.0.0", args.port), RequestHandler) as server:
            print(
                f"BoltTube share server listening on http://0.0.0.0:{args.port} "
                f"with library in {args.download_dir}",
                flush=True,
            )
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                print("Stopping share server...", flush=True)
        return 0

    raise ValueError(f"Unsupported command: {args.command}")


def main() -> int:
    parser = build_argument_parser()
    args = parser.parse_args()
    try:
        return run_command(args)
    except Exception as error:  # noqa: BLE001
        print(str(error), file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
