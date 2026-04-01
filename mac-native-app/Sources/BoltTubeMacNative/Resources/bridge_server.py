import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import uuid
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse
from typing import Optional, List, Dict, Union, Any

from pytubefix import YouTube

# Import local modules
try:
    from library import MediaLibrary
    from repository import MediaItem
except ImportError:
    from .library import MediaLibrary
    from .repository import MediaItem

def readable_size(num: int) -> str:
    for unit in ["B", "KB", "MB", "GB"]:
        if abs(num) < 1024.0: return f"{num:3.1f} {unit}"
        num /= 1024.0
    return f"{num:.1f} TB"

def sanitize_filename(name: str) -> str:
    name = re.sub(r'[^\w\s\u0600-\u06FF-]', '', name)
    return re.sub(r'\s+', ' ', name).strip()

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
        best_audio = yt.streams.filter(only_audio=True, subtype="mp4").order_by("abr").desc().first()
        audio_size = (best_audio.filesize or best_audio.filesize_approx or 0) if best_audio else 0
        for s in streams:
            if not s.resolution or s.resolution in seen_res: continue
            seen_res.add(s.resolution)
            v_size = s.filesize or s.filesize_approx or 0
            total_size = v_size if s.is_progressive else v_size + audio_size
            details = "single file" if s.is_progressive else "video+audio merge"
            formats.append({"id": str(s.itag), "title": s.resolution, "details": details, "filesize": readable_size(total_size)})
        return {"title": yt.title, "thumbnailUrl": thumb, "durationSeconds": int(getattr(yt, "length", 0)), "formats": formats}

    def download_with_progress(self, url: str, format_id: str) -> Dict[str, Any]:
        yt = YouTube(url)
        thumb = self._stable_t(url, yt)
        stream = yt.streams.get_by_itag(int(format_id))
        if not stream: raise ValueError("Format not found")
        
        audio = None if stream.is_progressive else yt.streams.filter(only_audio=True, subtype="mp4").order_by("abr").desc().first()
        video_total = int(stream.filesize or stream.filesize_approx or 0)
        audio_total = int(audio.filesize or audio.filesize_approx or 0) if audio is not None else 0
        total_bytes = video_total + audio_total
        per_stream: Dict[int, int] = {}

        def on_p(progress_stream, _chunk, remaining):
            downloaded = int(progress_stream.filesize or 0) - remaining
            per_stream[int(progress_stream.itag)] = max(downloaded, 0)
            now_down = sum(per_stream.values())
            print(json.dumps({"event": "progress", "downloadedBytes": now_down, "totalBytes": total_bytes, "fraction": now_down/total_bytes if total_bytes>0 else 0}), file=sys.stderr, flush=True)

        yt.register_on_progress_callback(on_p)
        t_name = f"{sanitize_filename(yt.title or 'video')}-{uuid.uuid4().hex[:8]}"
        print(json.dumps({"event": "starting", "title": yt.title, "tempName": t_name, "totalBytes": total_bytes}), file=sys.stderr, flush=True)
        
        target = self.library.download_dir
        if stream.is_progressive:
            f_path = Path(stream.download(output_path=str(target), filename=f"{t_name}.mp4"))
        else:
            ffmpeg = shutil.which("ffmpeg") or "/usr/local/bin/ffmpeg" or "/opt/homebrew/bin/ffmpeg"
            v_p = Path(stream.download(output_path=str(target), filename=f"{t_name}.v"))
            a_p = Path(audio.download(output_path=str(target), filename=f"{t_name}.a"))
            f_path = target / f"{t_name}.mp4"
            print(json.dumps({"event": "merging"}), file=sys.stderr, flush=True)
            subprocess.run([ffmpeg, "-nostdin", "-y", "-i", str(v_p), "-i", str(a_p), "-c:v", "copy", "-c:a", "aac", "-movflags", "+faststart", str(f_path)], capture_output=True, stdin=subprocess.DEVNULL)
            v_p.unlink(missing_ok=True); a_p.unlink(missing_ok=True)

        item = self.library.add(source_url=url, file_path=f_path, thumbnail_url=thumb, duration=int(getattr(yt, "length", 0)), title=getattr(yt, "title", f_path.stem))
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
            item = self.service.library.repo.get_item(media_id)
            if item and Path(item["file_path"]).exists():
                self.send_response(200); self.send_header("Content-Type", "video/mp4"); self.end_headers()
                with open(item["file_path"], "rb") as f: shutil.copyfileobj(f, self.wfile)
            else: self._send_json({"error": "not found"}, status=404)
    def do_POST(self):
        p = urlparse(self.path).path
        data = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if p == "/api/resolve": self._send_json(self.service.resolve(data["url"]))
        elif p == "/api/download": self._send_json(self.service.download_with_progress(data["url"], data["formatId"]))
        elif p == "/api/delete": self._send_json({"status": "deleted"} if self.service.library.remove(data["id"]) else {"status": "not_found"})
        elif p == "/api/refresh-metadata": self._send_json({"status": "ok", "metadata": self.service.library.refresh_metadata(data["id"])} if hasattr(self.service.library, 'refresh_metadata') else {"status": "error"})

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
