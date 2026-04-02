import argparse
import json
import multiprocessing as mp
import os
import re
import shutil
import subprocess
import sys
import time
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
RESOLVE_CLIENTS = ("ANDROID_VR", "IOS", "TV", "WEB")
CLIENT_PROBE_TIMEOUT = 6
download_jobs: Dict[str, Dict[str, Any]] = {}
download_jobs_lock = threading.RLock()
resolved_client_cache: Dict[str, str] = {}
resolved_client_cache_lock = threading.RLock()

def readable_size(num: int) -> str:
    for unit in ["B", "KB", "MB", "GB"]:
        if abs(num) < 1024.0: return f"{num:3.1f} {unit}"
        num /= 1024.0
    return f"{num:.1f} TB"

def sanitize_filename(name: str) -> str:
    name = re.sub(r'[^\w\s\u0600-\u06FF-]', '', name)
    return re.sub(r'\s+', ' ', name).strip()

def _emit_event(payload: Dict[str, Any], progress_callback=None):
    if progress_callback is not None:
        progress_callback(payload)
    print(json.dumps(payload), file=sys.stderr, flush=True)

def _run_bridge_cli(command: str, *, url: Optional[str] = None, format_id: Optional[str] = None, media_id: Optional[str] = None) -> Dict[str, Any]:
    if library is None:
        raise RuntimeError("Library not initialized")
    args = [sys.executable, __file__, command, "--download-dir", str(library.download_dir)]
    if url:
        args.extend(["--url", url])
    if format_id:
        args.extend(["--format-id", format_id])
    if media_id:
        args.extend(["--media-id", media_id])
    result = subprocess.run(args, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        stderr = (result.stderr or "").strip()
        raise RuntimeError(stderr or f"{command} failed")
    output = (result.stdout or "").strip()
    if not output:
        raise RuntimeError(f"{command} returned empty output")
    return json.loads(output)

def _extract_id(url: str) -> Optional[str]:
    try:
        from urllib.parse import urlparse, parse_qs
        if "youtu.be/" in url: return url.split("youtu.be/")[1].split("?")[0]
        if "/shorts/" in url: return url.split("/shorts/")[1].split("/")[0].split("?")[0]
        if "v=" in url: return parse_qs(urlparse(url).query).get("v", [None])[0]
    except: return None
    return None

def _canonicalize_youtube_url(url: str) -> str:
    video_id = _extract_id(url)
    return f"https://www.youtube.com/watch?v={video_id}" if video_id else url

def _stable_t(url: str, yt: Optional[YouTube] = None) -> str:
    v_id = _extract_id(url)
    return f"https://i.ytimg.com/vi/{v_id}/hqdefault.jpg" if v_id else (yt.thumbnail_url if yt else "")

def _probe_client_worker(url: str, client: str, result_queue):
    url = _canonicalize_youtube_url(url)
    try:
        yt = YouTube(url, client=client)
        _ = yt.title
        _ = yt.streams.filter(file_extension="mp4").first()
        result_queue.put({"ok": True, "client": client})
    except Exception as error:
        result_queue.put({"ok": False, "client": client, "error": str(error)})

def _client_candidates(url: str) -> List[str]:
    canonical = _canonicalize_youtube_url(url)
    with resolved_client_cache_lock:
        cached = resolved_client_cache.get(canonical)
    ordered = []
    if cached:
        ordered.append(cached)
    ordered.extend(client for client in RESOLVE_CLIENTS if client not in ordered)
    return ordered

def _remember_resolved_client(url: str, client: str):
    canonical = _canonicalize_youtube_url(url)
    with resolved_client_cache_lock:
        resolved_client_cache[canonical] = client

def _choose_client(url: str) -> str:
    ctx = mp.get_context("fork")
    last_error = "metadata probe failed"
    for client in _client_candidates(url):
        result_queue = ctx.Queue()
        process = ctx.Process(target=_probe_client_worker, args=(url, client, result_queue))
        process.start()
        process.join(CLIENT_PROBE_TIMEOUT)
        if process.is_alive():
            process.terminate()
            process.join()
            last_error = f"{client} timed out"
            continue
        if not result_queue.empty():
            result = result_queue.get()
            if result.get("ok"):
                _remember_resolved_client(url, client)
                return client
            last_error = result.get("error") or f"{client} failed"
    raise RuntimeError(last_error)

def _build_resolve_payload(url: str, client: str) -> Dict[str, Any]:
    url = _canonicalize_youtube_url(url)
    yt = YouTube(url, client=client)
    thumb = _stable_t(url, yt)
    
    # Try getting mp4 streams first (preferred for compatibility)
    streams = yt.streams.filter(file_extension="mp4").order_by("resolution")
    if not streams:
        # Fallback to all streams if mp4 is not available
        streams = yt.streams.order_by("resolution")
        
    formats = []
    seen_res = set()
    best_audio = yt.streams.filter(only_audio=True, subtype="mp4").order_by("abr").desc().first()
    audio_size = (best_audio.filesize or best_audio.filesize_approx or 0) if best_audio else 0
    
    for s in streams:
        if not s.resolution or s.resolution in seen_res:
            continue
        seen_res.add(s.resolution)
        v_size = s.filesize or s.filesize_approx or 0
        total_size = v_size if s.is_progressive else v_size + audio_size
        details = "single file" if s.is_progressive else "video+audio merge"
        formats.append({"id": str(s.itag), "title": s.resolution, "details": details, "filesize": readable_size(total_size)})
    
    if not formats:
        # Final desperate attempt: any progressive stream
        for s in yt.streams.filter(progressive=True):
            if s.resolution and s.resolution not in seen_res:
                seen_res.add(s.resolution)
                formats.append({"id": str(s.itag), "title": s.resolution, "details": "progressive", "filesize": readable_size(s.filesize or 0)})
                
    return {"title": yt.title, "thumbnail_url": thumb, "duration_seconds": int(getattr(yt, "length", 0)), "formats": formats}

def _resolve_payload_worker(url: str, client: str, result_queue):
    try:
        payload = _build_resolve_payload(url, client)
        result_queue.put({"ok": True, "client": client, "payload": payload})
    except Exception as error:
        result_queue.put({"ok": False, "client": client, "error": str(error)})

def _resolve_payload_with_fallback(url: str) -> Dict[str, Any]:
    ctx = mp.get_context("fork")
    last_error = "metadata probe failed"
    for client in _client_candidates(url):
        result_queue = ctx.Queue()
        process = ctx.Process(target=_resolve_payload_worker, args=(url, client, result_queue))
        process.start()
        process.join(CLIENT_PROBE_TIMEOUT)
        if process.is_alive():
            process.terminate()
            process.join()
            last_error = f"{client} timed out"
            continue
        if not result_queue.empty():
            result = result_queue.get()
            if result.get("ok"):
                _remember_resolved_client(url, client)
                payload = result.get("payload") or {}
                payload["resolved_client"] = client
                return payload
            last_error = result.get("error") or f"{client} failed"
    raise RuntimeError(last_error)

def _load_stream_for_format(url: str, format_id: str, preferred_client: Optional[str] = None):
    url = _canonicalize_youtube_url(url)
    clients = [preferred_client] if preferred_client else []
    clients.extend(client for client in _client_candidates(url) if client and client != preferred_client)
    last_error: Optional[Exception] = None

    for client in clients:
        try:
            yt = YouTube(url, client=client)
            stream = yt.streams.get_by_itag(int(format_id))
            if stream:
                _remember_resolved_client(url, client)
                return yt, stream, client
        except Exception as error:
            last_error = error

    if last_error:
        raise last_error
    raise ValueError("Format not found")

def _download_with_progress(url: str, format_id: str, client: str, existing_media_id: Optional[str] = None, progress_callback=None) -> Dict[str, Any]:
    url = _canonicalize_youtube_url(url)
    yt, stream, resolved_client = _load_stream_for_format(url, format_id, client)
    thumb = _stable_t(url, yt)
    _emit_event({"event": "client", "client": resolved_client}, progress_callback)

    audio = None if stream.is_progressive else yt.streams.filter(only_audio=True, subtype="mp4").order_by("abr").desc().first()
    video_total = int(stream.filesize or stream.filesize_approx or 0)
    audio_total = int(audio.filesize or audio.filesize_approx or 0) if audio is not None else 0
    total_bytes = video_total + audio_total
    per_stream: Dict[int, int] = {}

    def on_p(progress_stream, _chunk, remaining):
        downloaded = int(progress_stream.filesize or 0) - remaining
        per_stream[int(progress_stream.itag)] = max(downloaded, 0)
        now_down = sum(per_stream.values())
        _emit_event({"event": "progress", "downloadedBytes": now_down, "totalBytes": total_bytes, "fraction": now_down/total_bytes if total_bytes>0 else 0}, progress_callback)

    yt.register_on_progress_callback(on_p)
    t_name = f"{sanitize_filename(yt.title or 'video')}-{uuid.uuid4().hex[:8]}"
    _emit_event({"event": "starting", "title": yt.title, "tempName": t_name, "totalBytes": total_bytes}, progress_callback)

    target = library.download_dir
    if stream.is_progressive:
        f_path = Path(stream.download(output_path=str(target), filename=f"{t_name}.mp4"))
    else:
        ffmpeg = shutil.which("ffmpeg") or "/usr/local/bin/ffmpeg" or "/opt/homebrew/bin/ffmpeg"
        v_p = Path(stream.download(output_path=str(target), filename=f"{t_name}.v"))
        a_p = Path(audio.download(output_path=str(target), filename=f"{t_name}.a"))
        f_path = target / f"{t_name}.mp4"
        _emit_event({"event": "merging"}, progress_callback)
        subprocess.run([ffmpeg, "-nostdin", "-y", "-i", str(v_p), "-i", str(a_p), "-c:v", "copy", "-c:a", "aac", "-movflags", "+faststart", str(f_path)], capture_output=True, stdin=subprocess.DEVNULL)
        v_p.unlink(missing_ok=True)
        a_p.unlink(missing_ok=True)

    item = library.add(
        source_url=url,
        file_path=f_path,
        thumbnail_url=thumb,
        duration=int(getattr(yt, "length", 0)),
        title=getattr(yt, "title", f_path.stem),
        existing_media_id=existing_media_id,
    )
    return {"id": item.id, "stream_url": item.stream_url, "file_name": item.file_name}

def _set_download_job(media_id: str, **fields):
    with download_jobs_lock:
        current = download_jobs.get(media_id, {}).copy()
        current.update(fields)
        download_jobs[media_id] = current
        return current

def _start_offloaded_download(media_id: str, url: str, format_id: str, preferred_client: Optional[str] = None) -> Dict[str, Any]:
    item = library.repo.get_item(media_id) if library else None
    if not item:
        raise ValueError("Media item not found")

    with download_jobs_lock:
        current = download_jobs.get(media_id)
        if current and current.get("status") in {"queued", "resolving", "downloading", "merging"}:
            return current
        download_jobs[media_id] = {
            "mediaId": media_id,
            "status": "queued",
            "fraction": 0.0,
            "downloadedBytes": 0,
            "totalBytes": 0,
            "speedBytesPerSecond": 0.0,
            "error": "",
            "title": item.get("title") or "",
            "thumbnailUrl": item.get("thumbnail_url") or "",
            "sourceUrl": item.get("source_url") or url,
        }

    def worker():
        last_bytes = 0.0
        last_time = None

        def on_progress(payload: Dict[str, Any]):
            nonlocal last_bytes, last_time
            event = payload.get("event")
            if event == "starting":
                _set_download_job(
                    media_id,
                    status="downloading",
                    title=payload.get("title") or item.get("title") or "",
                    totalBytes=payload.get("totalBytes") or 0,
                    downloadedBytes=0,
                    fraction=0.0,
                    speedBytesPerSecond=0.0,
                )
            elif event == "progress":
                now = time.time()
                downloaded = float(payload.get("downloadedBytes") or 0.0)
                speed = 0.0
                if last_time is not None and now > last_time and downloaded >= last_bytes:
                    speed = (downloaded - last_bytes) / max(now - last_time, 0.001)
                last_time = now
                last_bytes = downloaded
                _set_download_job(
                    media_id,
                    status="downloading",
                    downloadedBytes=downloaded,
                    totalBytes=float(payload.get("totalBytes") or 0.0),
                    fraction=float(payload.get("fraction") or 0.0),
                    speedBytesPerSecond=speed,
                )
            elif event == "merging":
                _set_download_job(media_id, status="merging")
            elif event == "client":
                _set_download_job(media_id, client=payload.get("client") or "")

        try:
            _set_download_job(media_id, status="resolving")
            result = _download_with_progress(
                url=url,
                format_id=format_id,
                client=preferred_client or "WEB",
                existing_media_id=media_id,
                progress_callback=on_progress,
            )
            current = download_jobs.get(media_id, {})
            _set_download_job(
                media_id,
                status="completed",
                fraction=1.0,
                speedBytesPerSecond=0.0,
                downloadedBytes=current.get("downloadedBytes", 0),
                totalBytes=current.get("totalBytes", 0),
                fileName=result.get("file_name") or "",
                streamUrl=result.get("stream_url") or "",
            )
        except Exception as error:
            _set_download_job(media_id, status="failed", error=str(error), speedBytesPerSecond=0.0)

    threading.Thread(target=worker, daemon=True).start()
    return download_jobs[media_id]

def _add_offloaded_item(url: str, client: str) -> Dict[str, Any]:
    payload = _build_resolve_payload(url, client)
    item = library.add_offloaded(
        source_url=url,
        thumbnail_url=str(payload.get("thumbnail_url") or ""),
        duration=int(payload.get("duration_seconds") or 0),
        title=str(payload.get("title") or "Untitled"),
    )
    return {"id": item.id, "stream_url": item.stream_url, "file_name": item.file_name}

@app.route("/health")
def health(): return jsonify({"status": "ok", "port": 9864, "download_dir": str(library.download_dir) if library else ""})

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
        "id": str(item["id"]),
        "file_name": str(item.get("file_name") or ""),
        "stream_url": str(item.get("stream_url") or ""),
        "size": str(item.get("size") or ""),
        "created_at": str(item.get("created_at") or ""),
        "thumbnail_url": item.get("thumbnail_url"),
        "duration": item.get("duration", 0),
        "source_url": str(item.get("source_url") or ""),
        "is_downloaded": bool(item.get("is_downloaded", 1)),
        "title": str(item.get("title") or item["file_name"].replace(".mp4", "")),
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
            "id": str(item["id"]),
            "file_name": str(item.get("file_name") or ""),
            "title": str(item.get("title") or item["file_name"].replace(".mp4", "")),
            "stream_url": str(item.get("stream_url") or ""),
            "size": str(item.get("size") or ""),
            "created_at": str(item.get("created_at") or ""),
            "thumbnail_url": item.get("thumbnail_url"),
            "duration": item.get("duration", 0),
            "is_downloaded": bool(item.get("is_downloaded", 1)),
            "source_url": str(item.get("source_url") or ""),
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

@app.route("/api/list")
def list_library_v2():
    if not library: return jsonify({"items": []})
    return jsonify({"items": library.list_items()})

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
    try:
        return jsonify(_run_bridge_cli("resolve", url=data["url"]))
    except RuntimeError as error:
        return jsonify({"error": str(error)}), 504

@app.route("/api/download", methods=["POST"])
def download():
    data = request.json
    try:
        return jsonify(_download_with_progress(data["url"], data["formatId"], "WEB"))
    except ValueError as error:
        return jsonify({"error": str(error)}), 400
    except RuntimeError as error:
        return jsonify({"error": str(error)}), 504

@app.route("/api/offloaded/resolve", methods=["POST"])
def resolve_offloaded():
    data = request.json
    media_id = data.get("id")
    item = library.repo.get_item(media_id) if library and media_id else None
    if not item:
        return jsonify({"error": "Media item not found"}), 404
    try:
        payload = _run_bridge_cli("resolve", url=item["source_url"])
        payload["media_id"] = media_id
        return jsonify(payload)
    except RuntimeError as error:
        return jsonify({"error": str(error)}), 504

@app.route("/api/offloaded/download", methods=["POST"])
def download_offloaded():
    data = request.json
    media_id = data.get("id")
    format_id = data.get("formatId")
    preferred_client = data.get("preferredClient")
    item = library.repo.get_item(media_id) if library and media_id else None
    if not item:
        return jsonify({"error": "Media item not found"}), 404
    if not item.get("source_url"):
        return jsonify({"error": "Missing source URL"}), 400
    if not format_id:
        return jsonify({"error": "Missing format id"}), 400
    try:
        return jsonify(_start_offloaded_download(media_id, item["source_url"], format_id, preferred_client))
    except ValueError as error:
        return jsonify({"error": str(error)}), 400

@app.route("/api/offloaded/download-status/<media_id>")
def offloaded_download_status(media_id):
    item = library.repo.get_item(media_id) if library else None
    if item is None:
        return jsonify({"error": "Media item not found"}), 404
    with download_jobs_lock:
        job = download_jobs.get(media_id)
    if job:
        return jsonify(job)
    return jsonify({
        "mediaId": media_id,
        "status": "completed" if item.get("is_downloaded", 0) else "idle",
        "fraction": 1.0 if item.get("is_downloaded", 0) else 0.0,
        "downloadedBytes": 0,
        "totalBytes": 0,
        "speedBytesPerSecond": 0.0,
        "error": "",
        "title": item.get("title") or "",
        "thumbnailUrl": item.get("thumbnail_url") or "",
        "sourceUrl": item.get("source_url") or "",
        "fileName": item.get("file_name") or "",
        "streamUrl": item.get("stream_url") or "",
    })

@app.route("/api/add-offloaded", methods=["POST"])
def add_offloaded():
    data = request.json
    try:
        return jsonify(_run_bridge_cli("add-offloaded", url=data["url"]))
    except RuntimeError as error:
        return jsonify({"error": str(error)}), 504

@app.route("/api/delete", methods=["POST"])
def delete():
    return jsonify({"status": "deleted" if library.remove(request.json["id"]) else "not_found"})

@app.route("/api/offload", methods=["POST"])
def offload():
    if not library: return jsonify({"error": "not init"}), 500
    res = library.offload(request.json["id"])
    return jsonify({"status": "offloaded" if res else "not_found"})

@app.route("/api/refresh-metadata", methods=["POST"])
def refresh():
    return jsonify({"status": "ok", "metadata": library.refresh_metadata(request.json["id"])})

def main():
    global library
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["serve", "resolve", "download-progress", "add-offloaded", "list", "delete"])
    parser.add_argument("--download-dir", type=Path, required=True); parser.add_argument("--url"); parser.add_argument("--format-id"); parser.add_argument("--port", type=int, default=9864); parser.add_argument("--media-id")
    args = parser.parse_args()
    library = MediaLibrary(args.download_dir)
    
    if args.command == "serve":
        app.run(host="0.0.0.0", port=args.port, threaded=True)
    elif args.command == "resolve":
        print(json.dumps(_resolve_payload_with_fallback(args.url)))
    elif args.command == "download-progress":
        client = _choose_client(args.url)
        print(json.dumps(_download_with_progress(args.url, args.format_id, client, args.media_id)))
    elif args.command == "add-offloaded":
        payload = _resolve_payload_with_fallback(args.url)
        item = library.add_offloaded(
            source_url=args.url,
            thumbnail_url=str(payload.get("thumbnail_url") or ""),
            duration=int(payload.get("duration_seconds") or 0),
            title=str(payload.get("title") or "Untitled"),
        )
        print(json.dumps({"id": item.id, "stream_url": item.stream_url, "file_name": item.file_name}))
    elif args.command == "list": print(json.dumps({"items": library.list_items()}))
    elif args.command == "delete": print(json.dumps({"status": "deleted" if library.remove(args.media_id) else "not_found"}))

if __name__ == "__main__":
    main()
