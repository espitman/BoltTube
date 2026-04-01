import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import uuid
import threading
import sqlite3
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse
from typing import Optional, List, Dict, Union, Any

from pytubefix import YouTube

@dataclass
class MediaItem:
    id: str
    file_name: str
    file_path: str
    stream_url: str
    size: str
    created_at: str
    source_url: str = ""
    thumbnail_url: str = ""

def readable_size(num: int) -> str:
    for unit in ["B", "KB", "MB", "GB"]:
        if abs(num) < 1024.0: return f"{num:3.1f} {unit}"
        num /= 1024.0
    return f"{num:.1f} TB"

def sanitize_filename(name: str) -> str:
    name = re.sub(r'[^\w\s\u0600-\u06FF-]', '', name)
    return re.sub(r'\s+', ' ', name).strip()

class MediaLibrary:
    def __init__(self, download_dir: Path):
        self.download_dir = download_dir
        self.download_dir.mkdir(parents=True, exist_ok=True)
        self.db_path = self.download_dir / "bolttube.db"
        self.json_backup_path = self.download_dir / ".bolttube-library.json"
        self._lock = threading.Lock()
        self._init_db()
        self._migrate_from_json()

    def _init_db(self):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS media_items (
                    id TEXT PRIMARY KEY,
                    file_name TEXT NOT NULL,
                    file_path TEXT NOT NULL,
                    stream_url TEXT NOT NULL,
                    size TEXT,
                    created_at TEXT,
                    source_url TEXT,
                    thumbnail_url TEXT
                )
            """)
            conn.execute("""
                CREATE TABLE IF NOT EXISTS playlists (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT UNIQUE NOT NULL,
                    created_at TEXT
                )
            """)
            conn.execute("""
                CREATE TABLE IF NOT EXISTS playlist_items (
                    playlist_id INTEGER,
                    media_id TEXT,
                    added_at TEXT,
                    FOREIGN KEY(playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
                    FOREIGN KEY(media_id) REFERENCES media_items(id) ON DELETE CASCADE,
                    PRIMARY KEY(playlist_id, media_id)
                )
            """)

    def _migrate_from_json(self):
        if self.json_backup_path.exists():
            try:
                payload = json.loads(self.json_backup_path.read_text(encoding="utf-8"))
                items = payload.get("items", [])
                with sqlite3.connect(self.db_path) as conn:
                    for i in items:
                        conn.execute("""
                            INSERT OR IGNORE INTO media_items 
                            (id, file_name, file_path, stream_url, size, created_at, source_url, thumbnail_url)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """, (i["id"], i["file_name"], i["file_path"], i["stream_url"], i["size"], i["created_at"], i.get("source_url", ""), i.get("thumbnail_url", "")))
                # Rename to .bak to prevent re-migration
                self.json_backup_path.rename(self.json_backup_path.with_suffix(".json.bak"))
                print(f"MIGRATED {len(items)} items to SQLite", file=sys.stderr)
            except Exception as e:
                print(f"Migration error: {e}", file=sys.stderr)

    def _sync_disk(self):
        # Sync logic logic remains to reconcile files but we prioritize database items
        import unicodedata
        def norm(n: str) -> str: return unicodedata.normalize("NFD", n)
        
        with sqlite3.connect(self.db_path) as conn:
            rows = conn.execute("SELECT file_path FROM media_items").fetchall()
            db_paths = {norm(Path(r[0]).name) for r in rows}
            
            for file in self.download_dir.glob("*.mp4"):
                if norm(file.name) in db_paths: continue
                media_id = file.stem
                conn.execute("""
                    INSERT OR IGNORE INTO media_items (id, file_name, file_path, stream_url, size, created_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, (media_id, file.name, str(file.absolute()), f"/media/{media_id}", 
                      readable_size(file.stat().st_size), datetime.fromtimestamp(file.stat().st_mtime, tz=timezone.utc).isoformat()))

    def remove(self, media_id: str) -> bool:
        with self._lock:
            with sqlite3.connect(self.db_path) as conn:
                row = conn.execute("SELECT file_path FROM media_items WHERE id = ?", (media_id,)).fetchone()
                if row:
                    try: Path(row[0]).unlink(missing_ok=True)
                    except: pass
                    conn.execute("DELETE FROM media_items WHERE id = ?", (media_id,))
                    return True
        return False

    def list_items(self) -> List[Dict[str, Any]]:
        with self._lock:
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                rows = conn.execute("SELECT * FROM media_items ORDER BY created_at DESC").fetchall()
                return [
                    {
                        "id": r["id"],
                        "fileName": r["file_name"],
                        "streamUrl": r["stream_url"],
                        "size": r["size"],
                        "createdAt": r["created_at"],
                        "thumbnailUrl": r["thumbnail_url"]
                    }
                    for r in rows
                ]

    def add(self, *, source_url: str, file_path: Path, thumbnail_url: str = "") -> MediaItem:
        with self._lock:
            media_id = f"{file_path.stem}-{uuid.uuid4().hex[:8]}"
            final_p = file_path.with_name(f"{media_id}{file_path.suffix}")
            file_path.rename(final_p)
            item = MediaItem(id=media_id, file_name=final_p.name, file_path=str(final_p), stream_url=f"/media/{media_id}",
                            size=readable_size(final_p.stat().st_size), created_at=datetime.now(timezone.utc).isoformat(), 
                            source_url=source_url, thumbnail_url=thumbnail_url)
            
            with sqlite3.connect(self.db_path) as conn:
                conn.execute("""
                    INSERT INTO media_items (id, file_name, file_path, stream_url, size, created_at, source_url, thumbnail_url)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (item.id, item.file_name, item.file_path, item.stream_url, item.size, item.created_at, item.source_url, item.thumbnail_url))
            return item

class BridgeService:
    def __init__(self, download_dir: Path):
        self.library = MediaLibrary(download_dir)

    def _extract_id(self, url: str) -> Optional[str]:
        try:
            if "youtu.be/" in url: return url.split("youtu.be/")[1].split("?")[0]
            if "/shorts/" in url: return url.split("/shorts/")[1].split("/")[0].split("?")[0]
            if "v=" in url: return parse_qs(urlparse(url).query).get("v", [None])[0]
        except: return None

    def _stable_t(self, url: str, yt: Optional[YouTube] = None) -> str:
        v_id = self._extract_id(url)
        return f"https://i.ytimg.com/vi/{v_id}/hqdefault.jpg" if v_id else (yt.thumbnail_url if yt else "")

    def resolve(self, url: str) -> Dict[str, Any]:
        yt = YouTube(url)
        thumb = self._stable_t(url, yt)
        # Sort resolutions to match expected App order
        streams = yt.streams.filter(file_extension="mp4").order_by("resolution")
        formats = []
        seen_res = set()
        best_audio = yt.streams.filter(only_audio=True, subtype="mp4").order_by("abr").desc().first()
        audio_size = (best_audio.filesize or best_audio.filesize_approx or 0) if best_audio else 0
        for s in streams:
            if not s.resolution or s.resolution in seen_res: continue
            seen_res.add(s.resolution)
            video_size = s.filesize or s.filesize_approx or 0
            total_size = video_size if s.is_progressive else video_size + audio_size
            details = "single file" if s.is_progressive else "video+audio merge"
            formats.append({"id": str(s.itag), "title": s.resolution, "details": details, "filesize": readable_size(total_size)})
        return {"title": yt.title, "thumbnailUrl": thumb, "durationSeconds": int(getattr(yt, "length", 0)), "formats": formats}

    def download_with_progress(self, url: str, format_id: str) -> Dict[str, Any]:
        yt = YouTube(url)
        thumb = self._stable_t(url, yt)
        stream = yt.streams.get_by_itag(int(format_id))
        if not stream: raise ValueError("Format not found")
        
        audio = None if stream.is_progressive else yt.streams.filter(only_audio=True, subtype="mp4").order_by("abr").desc().first()
        if not stream.is_progressive and audio is None:
            raise ValueError("No compatible audio stream found")

        video_total = int(stream.filesize or stream.filesize_approx or 0)
        audio_total = int(audio.filesize or audio.filesize_approx or 0) if audio is not None else 0
        total_bytes = video_total + audio_total
        per_stream_downloaded: Dict[int, int] = {}

        def on_p(progress_stream, _chunk, remaining):
            stream_total = int(progress_stream.filesize or progress_stream.filesize_approx or 0)
            downloaded = max(stream_total - remaining, 0)
            if progress_stream.itag is not None:
                per_stream_downloaded[int(progress_stream.itag)] = downloaded
            total_downloaded = sum(per_stream_downloaded.values())
            print(json.dumps({
                "event": "progress",
                "downloadedBytes": total_downloaded,
                "totalBytes": total_bytes,
                "fraction": (total_downloaded / total_bytes) if total_bytes > 0 else 0,
            }), file=sys.stderr, flush=True)

        yt.register_on_progress_callback(on_p)
        
        t_name = f"{sanitize_filename(yt.title or 'video')}-{uuid.uuid4().hex[:8]}"
        print(json.dumps({"event": "starting", "title": yt.title, "tempName": t_name, "totalBytes": total_bytes}), file=sys.stderr, flush=True)
        
        target_dir = self.library.download_dir
        if stream.is_progressive:
            f_path = Path(stream.download(output_path=str(target_dir), filename=f"{t_name}.mp4"))
        else:
            ffmpeg = shutil.which("ffmpeg") or "/usr/local/bin/ffmpeg" or "/opt/homebrew/bin/ffmpeg"
            if os.path.exists(ffmpeg):
                v_p = Path(stream.download(output_path=str(target_dir), filename=f"{t_name}.video.{stream.subtype or 'mp4'}"))
                a_p = Path(audio.download(output_path=str(target_dir), filename=f"{t_name}.audio.{audio.subtype or 'm4a'}"))
                f_path = target_dir / f"{t_name}.mp4"
                print(json.dumps({"event": "merging"}), file=sys.stderr, flush=True)
                completed = subprocess.run([
                    ffmpeg, "-nostdin", "-y", "-i", str(v_p), "-i", str(a_p),
                    "-c:v", "copy", "-c:a", "aac", "-movflags", "+faststart", str(f_path)
                ], capture_output=True, text=True, stdin=subprocess.DEVNULL)
                v_p.unlink(missing_ok=True); a_p.unlink(missing_ok=True)
                if completed.returncode != 0: raise ValueError(f"ffmpeg failed: {completed.stderr}")
            else:
                fallback = yt.streams.filter(progressive=True, file_extension="mp4").order_by("resolution").desc().first()
                f_path = Path(fallback.download(output_path=str(target_dir), filename=f"{t_name}.mp4"))
            
        item = self.library.add(source_url=url, file_path=f_path, thumbnail_url=thumb)
        return {"id": item.id, "streamUrl": item.stream_url, "fileName": item.file_name}

    def list_items(self):
        return {"items": self.library.list_items()}

class RequestHandler(BaseHTTPRequestHandler):
    service: BridgeService
    def _send_json(self, data, status=200):
        self.send_response(status); self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*"); self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode("utf-8"))
    def do_GET(self):
        p = urlparse(self.path).path
        if p == "/health": self._send_json({"status": "ok"})
        elif p == "/api/items": self._send_json(self.service.list_items())
        elif p.startswith("/media/"):
            media_id = unquote(p.removeprefix("/media/"))
            # Fetch path from DB for serving
            with sqlite3.connect(self.service.library.db_path) as conn:
                row = conn.execute("SELECT file_path FROM media_items WHERE id = ?", (media_id,)).fetchone()
                if row and Path(row[0]).exists():
                    self.send_response(200); self.send_header("Content-Type", "video/mp4"); self.end_headers()
                    with open(row[0], "rb") as f: shutil.copyfileobj(f, self.wfile)
                else: self._send_json({"error": "not found"}, status=404)
    def do_POST(self):
        p = urlparse(self.path).path
        data = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if p == "/api/resolve": self._send_json(self.service.resolve(data["url"]))
        elif p == "/api/download": self._send_json(self.service.download_with_progress(data["url"], data["formatId"]))
        elif p == "/api/delete": self._send_json({"status": "deleted"} if self.service.library.remove(data["id"]) else {"status": "not_found"})

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["serve", "resolve", "download-progress", "list", "delete"])
    parser.add_argument("--download-dir", type=Path, required=True); parser.add_argument("--url")
    parser.add_argument("--format-id"); parser.add_argument("--port", type=int, default=9864); parser.add_argument("--media-id")
    args = parser.parse_args(); service = BridgeService(args.download_dir)
    if args.command == "serve":
        RequestHandler.service = service
        with ThreadingHTTPServer(("0.0.0.0", args.port), RequestHandler) as s: s.serve_forever()
    elif args.command == "resolve": print(json.dumps(service.resolve(args.url)))
    elif args.command == "download-progress": print(json.dumps(service.download_with_progress(args.url, args.format_id)))
    elif args.command == "list": print(json.dumps(service.list_items()))
    elif args.command == "delete": print(json.dumps({"status": "deleted" if service.library.remove(args.media_id) else "not_found"}))

if __name__ == "__main__":
    main()
