import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import uuid
import threading
from pathlib import Path
from urllib.parse import unquote
from typing import Optional, List, Dict, Union, Any

from flask import Flask, request, jsonify, send_file, Response
from flask_cors import CORS
from pytubefix import YouTube

# Import local modules
try:
    from library import MediaLibrary
    from repository import MediaItem
except ImportError:
    from .library import MediaLibrary
    from .repository import MediaItem

app = Flask(__name__)
CORS(app)
library: Optional[MediaLibrary] = None

def readable_size(num: int) -> str:
    for unit in ["B", "KB", "MB", "GB"]:
        if abs(num) < 1024.0: return f"{num:3.1f} {unit}"
        num /= 1024.0
    return f"{num:.1f} TB"

def sanitize_filename(name: str) -> str:
    name = re.sub(r'[^\w\s\u0600-\u06FF-]', '', name)
    return re.sub(r'\s+', ' ', name).strip()

def _extract_id(url: str) -> Optional[str]:
    try:
        from urllib.parse import urlparse, parse_qs
        if "youtu.be/" in url: return url.split("youtu.be/")[1].split("?")[0]
        if "/shorts/" in url: return url.split("/shorts/")[1].split("/")[0].split("?")[0]
        if "v=" in url: return parse_qs(urlparse(url).query).get("v", [None])[0]
    except: return None
    return None

def _stable_t(url: str, yt: Optional[YouTube] = None) -> str:
    v_id = _extract_id(url)
    return f"https://i.ytimg.com/vi/{v_id}/hqdefault.jpg" if v_id else (yt.thumbnail_url if yt else "")

@app.route("/health")
def health(): return jsonify({"status": "ok", "port": 9864, "downloadDir": str(library.download_dir) if library else ""})

@app.route("/api/items")
def list_library():
    return jsonify({"items": library.list_items() if library else []})

@app.route("/api/playlists")
def list_playlists():
    if not library: return jsonify({"items": []})
    return jsonify({"items": library.repo.get_playlists()})

@app.route("/api/playlists/create", methods=["POST"])
def create_playlist():
    if not library: return jsonify({"error": "not init"}), 500
    data = request.json
    p_id = library.repo.create_playlist(data["name"], data.get("thumbnailUrl"))
    return jsonify({"status": "ok", "id": p_id})

@app.route("/api/playlists/add", methods=["POST"])
def add_to_playlist():
    if not library: return jsonify({"error": "not init"}), 500
    data = request.json
    library.repo.add_to_playlist(int(data["playlistId"]), data["mediaId"])
    return jsonify({"status": "ok"})

@app.route("/api/playlists/delete", methods=["POST"])
def delete_playlist():
    if not library: return jsonify({"error": "not init"}), 500
    library.repo.delete_playlist(int(request.json["id"]))
    return jsonify({"status": "ok"})

@app.route("/api/playlists/update", methods=["POST"])
def update_playlist():
    if not library: return jsonify({"error": "not init"}), 500
    data = request.json
    library.repo.update_playlist(int(data["id"]), data["name"])
    return jsonify({"status": "ok"})

@app.route("/api/playlists/<int:p_id>/items")
def get_playlist_items(p_id):
    if not library: return jsonify({"items": []})
    raw_items = library.repo.get_playlist_items(p_id)
    items = [{
        "id": item["id"],
        "fileName": item["file_name"],
        "streamUrl": item["stream_url"],
        "size": item["size"],
        "createdAt": item["created_at"],
        "thumbnailUrl": item.get("thumbnail_url"),
        "duration": item.get("duration", 0),
        "title": item.get("title") or item["file_name"].replace(".mp4", ""),
    } for item in raw_items]
    return jsonify({"items": items})

@app.route("/api/channels/<int:channel_id>/content")
def get_channel_content(channel_id):
    if not library: return jsonify({"items": []})
    playlists = library.repo.get_channel_playlists(channel_id)
    content = []
    for p in playlists:
        raw_items = library.repo.get_playlist_items(p["id"])[:10]
        items = [{
            "id": item["id"],
            "fileName": item["file_name"],
            "title": item.get("title") or item["file_name"].replace(".mp4", ""),
            "streamUrl": item["stream_url"],
            "size": item["size"],
            "createdAt": item["created_at"],
            "thumbnailUrl": item.get("thumbnail_url"),
            "duration": item.get("duration", 0),
        } for item in raw_items]
        content.append({
            "playlist": {
                "id": p["id"],
                "name": p["name"],
                "thumbnail_url": p.get("thumbnail_url"),
                "created_at": p["created_at"],
                "item_count": p.get("item_count", 0),
            },
            "items": items
        })
    return jsonify({"content": content})

# --- NEW: Channels API ---
@app.route("/api/channels")
def list_channels():
    if not library: return jsonify({"items": []})
    return jsonify({"items": library.repo.get_channels()})

@app.route("/api/channels/create", methods=["POST"])
def create_channel():
    if not library: return jsonify({"error": "not init"}), 500
    data = request.json
    c_id = library.repo.create_channel(data["name"], data.get("thumbnailUrl"))
    return jsonify({"status": "ok", "id": c_id})

@app.route("/api/channels/add", methods=["POST"])
def add_playlist_to_channel():
    if not library: return jsonify({"error": "not init"}), 500
    data = request.json
    library.repo.add_playlist_to_channel(int(data["channelId"]), int(data["playlistId"]))
    return jsonify({"status": "ok"})

@app.route("/api/channels/delete", methods=["POST"])
def delete_channel():
    if not library: return jsonify({"error": "not init"}), 500
    library.repo.delete_channel(int(request.json["id"]))
    return jsonify({"status": "ok"})

@app.route("/api/channels/update", methods=["POST"])
def update_channel():
    if not library: return jsonify({"error": "not init"}), 500
    data = request.json
    try:
        library.repo.update_channel(int(data["id"]), data["name"])
        return jsonify({"status": "ok"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 400

@app.route("/media/<media_id>")
def serve_video(media_id):
    if not library: return "Not initialized", 500
    item = library.repo.get_item(media_id)
    if item and Path(item["file_path"]).exists():
        # send_file handles range requests automatically in Flask
        return send_file(item["file_path"], mimetype="video/mp4", as_attachment=False)
    return "Not found", 404

@app.route("/api/resolve", methods=["POST"])
def resolve():
    data = request.json
    yt = YouTube(data["url"])
    thumb = _stable_t(data["url"], yt)
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
    return jsonify({"title": yt.title, "thumbnailUrl": thumb, "durationSeconds": int(getattr(yt, "length", 0)), "formats": formats})

@app.route("/api/download", methods=["POST"])
def download():
    data = request.json
    url, format_id = data["url"], data["formatId"]
    yt = YouTube(url)
    thumb = _stable_t(url, yt)
    stream = yt.streams.get_by_itag(int(format_id))
    if not stream: return jsonify({"error": "Format not found"}), 400
    
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
    
    target = library.download_dir
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

    item = library.add(source_url=url, file_path=f_path, thumbnail_url=thumb, duration=int(getattr(yt, "length", 0)), title=getattr(yt, "title", f_path.stem))
    return jsonify({"id": item.id, "streamUrl": item.stream_url, "fileName": item.file_name})

@app.route("/api/delete", methods=["POST"])
def delete():
    return jsonify({"status": "deleted" if library.remove(request.json["id"]) else "not_found"})

@app.route("/api/refresh-metadata", methods=["POST"])
def refresh():
    return jsonify({"status": "ok", "metadata": library.refresh_metadata(request.json["id"])})

def main():
    global library
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["serve", "resolve", "download-progress", "list", "delete"])
    parser.add_argument("--download-dir", type=Path, required=True); parser.add_argument("--url"); parser.add_argument("--format-id"); parser.add_argument("--port", type=int, default=9864); parser.add_argument("--media-id")
    args = parser.parse_args()
    library = MediaLibrary(args.download_dir)
    
    if args.command == "serve":
        app.run(host="0.0.0.0", port=args.port, threaded=True)
    elif args.command == "resolve": print(json.dumps(library.resolve(args.url) if hasattr(library, 'resolve') else {}))
    elif args.command == "list": print(json.dumps({"items": library.list_items()}))
    elif args.command == "delete": print(json.dumps({"status": "deleted" if library.remove(args.media_id) else "not_found"}))

if __name__ == "__main__":
    main()
