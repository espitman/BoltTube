import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import uuid
import threading
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
        self.manifest_path = self.download_dir / ".bolttube-library.json"
        self._items = {}
        self._lock = threading.Lock()
        self._load()

    def _load(self):
        if self.manifest_path.exists():
            try:
                payload = json.loads(self.manifest_path.read_text(encoding="utf-8"))
                for raw_item in payload.get("items", []):
                    item = MediaItem(**raw_item)
                    if Path(item.file_path).exists(): self._items[item.id] = item
            except: pass
        self._sync_disk()

    def _save(self):
        payload = {"items": [asdict(item) for item in self._items.values() if Path(item.file_path).exists()]}
        self.manifest_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")

    def _sync_disk(self):
        import unicodedata
        def norm(n: str) -> str: return unicodedata.normalize("NFD", n)
        current_f = {norm(Path(i.file_path).name): i for i in self._items.values()}
        for file in self.download_dir.glob("*.mp4"):
            if norm(file.name) in current_f: continue
            media_id = file.stem
            self._items[media_id] = MediaItem(id=media_id, file_name=file.name, file_path=str(file.absolute()),
                                              stream_url=f"/media/{media_id}", size=readable_size(file.stat().st_size),
                                              created_at=datetime.fromtimestamp(file.stat().st_mtime, tz=timezone.utc).isoformat())
        self._save()

    def remove(self, media_id: str) -> bool:
        with self._lock:
            if media_id in self._items:
                item = self._items[media_id]
                try:
                    p = Path(item.file_path)
                    if p.exists(): p.unlink()
                except: pass
                del self._items[media_id]
                self._save()
                return True
        return False

    def list_items(self) -> List[Dict[str, Any]]:
        with self._lock:
            items = sorted(self._items.values(), key=lambda i: i.created_at, reverse=True)
            return [{"id": i.id, "fileName": i.file_name, "streamUrl": i.stream_url, "size": i.size, 
                    "createdAt": i.created_at, "thumbnailUrl": i.thumbnail_url} for i in items]

    def add(self, *, source_url: str, file_path: Path, thumbnail_url: str = "") -> MediaItem:
        with self._lock:
            media_id = f"{file_path.stem}-{uuid.uuid4().hex[:8]}"
            final_p = file_path.with_name(f"{media_id}{file_path.suffix}")
            file_path.rename(final_p)
            item = MediaItem(id=media_id, file_name=final_p.name, file_path=str(final_p), stream_url=f"/media/{media_id}",
                            size=readable_size(final_p.stat().st_size), created_at=datetime.now(timezone.utc).isoformat(), 
                            source_url=source_url, thumbnail_url=thumbnail_url)
            self._items[item.id] = item
            self._save()
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
        streams = yt.streams.filter(file_extension="mp4").order_by("resolution")
        formats = []
        seen_res = set()
        for s in streams:
            if not s.resolution or s.resolution in seen_res: continue
            seen_res.add(s.resolution)
            formats.append({"id": str(s.itag), "title": s.resolution, "details": "AVC1", "filesize": readable_size(s.filesize or s.filesize_approx or 0)})
        return {"title": yt.title, "thumbnailUrl": thumb, "durationSeconds": int(getattr(yt, "length", 0)), "formats": formats}

    def download_with_progress(self, url: str, format_id: str) -> Dict[str, Any]:
        def on_p(stream, chunk, remaining):
            total = stream.filesize
            down = total - remaining
            print(json.dumps({"event": "progress", "downloadedBytes": down, "totalBytes": total, "fraction": down/total if total>0 else 0}), file=sys.stderr, flush=True)
        
        yt = YouTube(url, on_progress_callback=on_p)
        thumb = self._stable_t(url, yt)
        stream = yt.streams.get_by_itag(int(format_id))
        if not stream: raise ValueError("Format not found")
        
        t_name = f"{sanitize_filename(yt.title or 'video')}-{uuid.uuid4().hex[:8]}"
        print(json.dumps({"event": "starting", "title": yt.title, "tempName": t_name}), file=sys.stderr, flush=True)
        
        target_dir = self.library.download_dir
        if stream.is_progressive:
            f_path = Path(stream.download(output_path=str(target_dir), filename=f"{t_name}.mp4"))
        else:
            ffmpeg = shutil.which("ffmpeg") or "/usr/local/bin/ffmpeg" or "/opt/homebrew/bin/ffmpeg"
            audio = yt.streams.filter(only_audio=True, subtype="mp4").order_by("abr").desc().first()
            if os.path.exists(ffmpeg):
                if audio is None:
                    raise ValueError("No compatible audio stream found")
                v_p = Path(stream.download(output_path=str(target_dir), filename=f"{t_name}.video.{stream.subtype or 'mp4'}"))
                a_p = Path(audio.download(output_path=str(target_dir), filename=f"{t_name}.audio.{audio.subtype or 'm4a'}"))
                f_path = target_dir / f"{t_name}.mp4"
                print(json.dumps({"event": "merging"}), file=sys.stderr, flush=True)
                completed = subprocess.run(
                    [
                        ffmpeg,
                        "-nostdin",
                        "-y",
                        "-i", str(v_p),
                        "-i", str(a_p),
                        "-c:v", "copy",
                        "-c:a", "aac",
                        "-movflags", "+faststart",
                        str(f_path),
                    ],
                    capture_output=True,
                    text=True,
                    stdin=subprocess.DEVNULL,
                )
                v_p.unlink(missing_ok=True)
                a_p.unlink(missing_ok=True)
                if completed.returncode != 0:
                    raise ValueError(completed.stderr.strip() or "ffmpeg merge failed")
            else:
                # Fallback to the best progressive stream if ffmpeg is missing
                fallback = yt.streams.filter(progressive=True, file_extension="mp4").order_by("resolution").desc().first()
                f_path = Path(fallback.download(output_path=str(target_dir), filename=f"{t_name}.mp4"))
            
        item = self.library.add(source_url=url, file_path=f_path, thumbnail_url=thumb)
        return {"id": item.id, "streamUrl": item.stream_url, "fileName": item.file_name}

class RequestHandler(BaseHTTPRequestHandler):
    service: BridgeService
    def _send_json(self, data, status=200):
        self.send_response(status); self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*"); self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode("utf-8"))
    def do_GET(self):
        p = urlparse(self.path).path
        if p == "/health": self._send_json({"status": "ok"})
        elif p == "/api/items": self._send_json(self.service.library.list_items() if hasattr(self.service.library, "list_items") else {"items": []})
        elif p.startswith("/media/"):
            media_id = unquote(p.removeprefix("/media/"))
            item = self.service.library._items.get(media_id)
            if item and Path(item.file_path).exists():
                self.send_response(200); self.send_header("Content-Type", "video/mp4"); self.end_headers()
                with open(item.file_path, "rb") as f: shutil.copyfileobj(f, self.wfile)
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
    elif args.command == "list": print(json.dumps({"items": service.library.list_items()}))
    elif args.command == "delete": print(json.dumps({"status": "deleted" if service.library.remove(args.media_id) else "not_found"}))

if __name__ == "__main__":
    main()
