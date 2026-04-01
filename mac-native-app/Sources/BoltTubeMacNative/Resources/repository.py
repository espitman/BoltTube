import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, List, Dict, Any

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
    duration: int = 0

class MediaRepository:
    def __init__(self, db_path: Path):
        self.db_path = db_path
        self._init_db()

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
                    thumbnail_url TEXT,
                    duration INTEGER DEFAULT 0
                )
            """)
            conn.execute("""
                CREATE TABLE IF NOT EXISTS playlists (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT UNIQUE NOT NULL,
                    created_at TEXT
                )
            """)
            try:
                conn.execute("ALTER TABLE media_items ADD COLUMN duration INTEGER DEFAULT 0")
            except sqlite3.OperationalError: pass # Already exists

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

    def save_item(self, item: MediaItem):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT OR REPLACE INTO media_items 
                (id, file_name, file_path, stream_url, size, created_at, source_url, thumbnail_url, duration)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (item.id, item.file_name, item.file_path, item.stream_url, item.size, item.created_at, item.source_url, item.thumbnail_url, item.duration))

    def delete_item(self, media_id: str):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("DELETE FROM media_items WHERE id = ?", (media_id,))

    def get_item(self, media_id: str) -> Optional[Dict[str, Any]]:
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            row = conn.execute("SELECT id, file_name, file_path, stream_url, size, created_at, source_url, thumbnail_url, duration FROM media_items WHERE id = ?", (media_id,)).fetchone()
            return dict(row) if row else None

    def get_all_items(self) -> List[Dict[str, Any]]:
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute("SELECT id, file_name, file_path, stream_url, size, created_at, source_url, thumbnail_url, duration FROM media_items ORDER BY created_at DESC").fetchall()
            return [dict(r) for r in rows]
