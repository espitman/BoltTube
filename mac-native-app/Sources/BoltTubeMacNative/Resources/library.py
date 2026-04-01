import json
import uuid
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
        self._lock = threading.Lock()
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
            return [
                {
                    "id": r["id"],
                    "fileName": r["file_name"],
                    "streamUrl": r["stream_url"],
                    "size": r["size"],
                    "createdAt": r["created_at"],
                    "thumbnailUrl": r["thumbnail_url"]
                }
                for r in items
            ]

    def remove(self, media_id: str) -> bool:
        with self._lock:
            item = self.repo.get_item(media_id)
            if item:
                Path(item["file_path"]).unlink(missing_ok=True)
                self.repo.delete_item(media_id)
                return True
        return False

    def add(self, *, source_url: str, file_path: Path, thumbnail_url: str = "") -> MediaItem:
        with self._lock:
            media_id = f"{file_path.stem}-{uuid.uuid4().hex[:8]}"
            final_p = file_path.with_name(f"{media_id}{file_path.suffix}")
            file_path.rename(final_p)
            item = MediaItem(id=media_id, file_name=final_p.name, file_path=str(final_p), stream_url=f"/media/{media_id}",
                            size=readable_size_internal(final_p.stat().st_size), created_at=datetime.now(timezone.utc).isoformat(), 
                            source_url=source_url, thumbnail_url=thumbnail_url)
            self.repo.save_item(item)
            return item

def readable_size_internal(num: int) -> str:
    for unit in ["B", "KB", "MB", "GB"]:
        if abs(num) < 1024.0: return f"{num:3.1f} {unit}"
        num /= 1024.0
    return f"{num:.1f} TB"
