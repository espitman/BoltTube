import json
import sqlite3
import uuid
import subprocess
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Dict, Any, Optional

try:
    from repository import MediaRepository, MediaItem
except ImportError:
    from .repository import MediaRepository, MediaItem

class MediaLibrary:
    def __init__(self, download_dir: Path):
        self.download_dir = download_dir
        self.download_dir.mkdir(parents=True, exist_ok=True)
        self.repo = MediaRepository(self.download_dir / "bolttube.db")
        self._lock = threading.RLock()
        self._migrate_legacy_json()

    def _migrate_legacy_json(self):
        json_path = self.download_dir / ".bolttube-library.json"
        if json_path.exists():
            try:
                payload = json.loads(json_path.read_text(encoding="utf-8"))
                items = payload.get("items", [])
                for i in items:
                    self.repo.save_item(MediaItem(**i))
                json_path.rename(json_path.with_suffix(".json.bak"))
            except: pass

    def list_items(self) -> List[Dict[str, Any]]:
        with self._lock:
            items = self.repo.get_all_items()
            result = []
            for r in items:
                result.append({
                    "id": r["id"],
                    "fileName": r["file_name"],
                    "streamUrl": r["stream_url"],
                    "size": r["size"],
                    "createdAt": r["created_at"],
                    "thumbnailUrl": r["thumbnail_url"],
                    "duration": r.get("duration", 0)
                })
            return result

    def reprobe_item(self, item_id: str, file_path: str):
        ffmpeg_bin = self.get_ffmpeg_path()
        ffprobe_bin = ffmpeg_bin.replace("ffmpeg", "ffprobe")
        try:
            cmd = [ffprobe_bin, "-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", file_path]
            res = subprocess.run(cmd, capture_output=True, text=True)
            data = json.loads(res.stdout)
            duration = int(float(data.get("format", {}).get("duration", 0)))
            if duration > 0:
                with self._lock:
                    with sqlite3.connect(self.repo.db_path) as conn:
                        # Direct update to avoid MediaItem conversion overhead if not needed 
                        conn.execute("UPDATE media_items SET duration = ? WHERE id = ?", (duration, item_id))
                return duration
        except: pass
        return 0

    def get_ffmpeg_path(self) -> str:
        for p in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]:
            if Path(p).exists(): return p
        return "ffmpeg"

    def remove(self, media_id: str) -> bool:
        with self._lock:
            item = self.repo.get_item(media_id)
            if item:
                Path(item["file_path"]).unlink(missing_ok=True)
                self.repo.delete_item(media_id)
                return True
        return False

    def add(self, *, source_url: str, file_path: Path, thumbnail_url: str = "", duration: int = 0) -> MediaItem:
        with self._lock:
            media_id = f"{file_path.stem}-{uuid.uuid4().hex[:8]}"
            final_p = file_path.with_name(f"{media_id}{file_path.suffix}")
            file_path.rename(final_p)
            item = MediaItem(id=media_id, file_name=final_p.name, file_path=str(final_p), stream_url=f"/media/{media_id}",
                            size=readable_size_internal(final_p.stat().st_size), created_at=datetime.now(timezone.utc).isoformat(), 
                            source_url=source_url, thumbnail_url=thumbnail_url, duration=duration)
            self.repo.save_item(item)
            return item

def readable_size_internal(num: int) -> str:
    for unit in ["B", "KB", "MB", "GB"]:
        if abs(num) < 1024.0: return f"{num:3.1f} {unit}"
        num /= 1024.0
    return f"{num:.1f} TB"
