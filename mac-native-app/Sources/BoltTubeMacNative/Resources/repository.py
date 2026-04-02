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
    title: str = ""
    is_downloaded: int = 1

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
                    duration INTEGER DEFAULT 0,
                    title TEXT,
                    is_downloaded INTEGER DEFAULT 1
                )
            """)
            conn.execute("""
                CREATE TABLE IF NOT EXISTS playlists (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT UNIQUE NOT NULL,
                    thumbnail_url TEXT,
                    created_at TEXT
                )
            """)
            # NEW: Channels Table
            conn.execute("""
                CREATE TABLE IF NOT EXISTS channels (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT UNIQUE NOT NULL,
                    thumbnail_url TEXT,
                    created_at TEXT
                )
            """)
            # NEW: Channel Playlists (Junction)
            conn.execute("""
                CREATE TABLE IF NOT EXISTS channel_playlists (
                    channel_id INTEGER,
                    playlist_id INTEGER,
                    added_at TEXT,
                    FOREIGN KEY(channel_id) REFERENCES channels(id) ON DELETE CASCADE,
                    FOREIGN KEY(playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
                    PRIMARY KEY(channel_id, playlist_id)
                )
            """)
            try: conn.execute("ALTER TABLE playlists ADD COLUMN thumbnail_url TEXT")
            except sqlite3.OperationalError: pass
            try: conn.execute("ALTER TABLE media_items ADD COLUMN is_downloaded INTEGER DEFAULT 1")
            except sqlite3.OperationalError: pass

            conn.execute("""
                CREATE TABLE IF NOT EXISTS playlist_items (
                    playlist_id INTEGER,
                    media_id TEXT,
                    added_at TEXT,
                    sort_order INTEGER DEFAULT 0,
                    FOREIGN KEY(playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
                    FOREIGN KEY(media_id) REFERENCES media_items(id) ON DELETE CASCADE,
                    PRIMARY KEY(playlist_id, media_id)
                )
            """)
            try: conn.execute("ALTER TABLE playlist_items ADD COLUMN sort_order INTEGER DEFAULT 0")
            except sqlite3.OperationalError: pass

    def save_item(self, item: MediaItem):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT OR REPLACE INTO media_items 
                (id, file_name, file_path, stream_url, size, created_at, source_url, thumbnail_url, duration, title, is_downloaded)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (item.id, item.file_name, item.file_path, item.stream_url, item.size, item.created_at, item.source_url, item.thumbnail_url, item.duration, item.title, getattr(item, 'is_downloaded', 1)))

    def delete_item(self, media_id: str):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("DELETE FROM media_items WHERE id = ?", (media_id,))

    def get_item(self, media_id: str) -> Optional[Dict[str, Any]]:
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            row = conn.execute("SELECT id, file_name, file_path, stream_url, size, created_at, source_url, thumbnail_url, duration, title, is_downloaded FROM media_items WHERE id = ?", (media_id,)).fetchone()
            return dict(row) if row else None

    def get_all_items(self) -> List[Dict[str, Any]]:
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute("SELECT id, file_name, file_path, stream_url, size, created_at, source_url, thumbnail_url, duration, title, is_downloaded FROM media_items ORDER BY created_at DESC").fetchall()
            return [dict(r) for r in rows]

    def create_playlist(self, name: str, thumbnail_url: Optional[str] = None) -> int:
        from datetime import datetime
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute("INSERT INTO playlists (name, thumbnail_url, created_at) VALUES (?, ?, ?)", (name, thumbnail_url, datetime.now().isoformat()))
            return cursor.lastrowid

    def get_playlists(self) -> List[Dict[str, Any]]:
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute("""
                SELECT p.*, COUNT(pi.media_id) as item_count 
                FROM playlists p 
                LEFT JOIN playlist_items pi ON p.id = pi.playlist_id 
                GROUP BY p.id 
                ORDER BY p.created_at DESC
            """).fetchall()
            return [dict(r) for r in rows]

    def add_to_playlist(self, playlist_id: int, media_id: str):
        from datetime import datetime
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("INSERT OR IGNORE INTO playlist_items (playlist_id, media_id, added_at) VALUES (?, ?, ?)", (playlist_id, media_id, datetime.now().isoformat()))
            conn.execute("""
                UPDATE playlists 
                SET thumbnail_url = (SELECT thumbnail_url FROM media_items WHERE id = ?) 
                WHERE id = ? AND (thumbnail_url IS NULL OR thumbnail_url = '')
            """, (media_id, playlist_id))

    def get_playlist_items(self, playlist_id: int) -> List[Dict[str, Any]]:
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute("""
                SELECT m.* FROM media_items m
                JOIN playlist_items pi ON m.id = pi.media_id
                WHERE pi.playlist_id = ?
                ORDER BY pi.added_at ASC
            """, (playlist_id,)).fetchall()
            return [dict(r) for r in rows]

    def update_playlist(self, playlist_id: int, name: str):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("UPDATE playlists SET name = ? WHERE id = ?", (name, playlist_id))

    def delete_playlist(self, playlist_id: int):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("DELETE FROM playlists WHERE id = ?", (playlist_id,))

    def set_download_status(self, media_id: str, status: int):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("UPDATE media_items SET is_downloaded = ? WHERE id = ?", (status, media_id))

    # --- NEW: Channels ---
    def create_channel(self, name: str, thumb: Optional[str] = None) -> int:
        from datetime import datetime
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute("INSERT INTO channels (name, thumbnail_url, created_at) VALUES (?, ?, ?)", (name, thumb, datetime.now().isoformat()))
            return cursor.lastrowid

    def get_channels(self) -> List[Dict[str, Any]]:
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute("""
                SELECT c.*, COUNT(cp.playlist_id) as playlist_count 
                FROM channels c 
                LEFT JOIN channel_playlists cp ON c.id = cp.channel_id 
                GROUP BY c.id 
                ORDER BY c.created_at DESC
            """).fetchall()
            return [dict(r) for r in rows]

    def add_playlist_to_channel(self, channel_id: int, playlist_id: int):
        from datetime import datetime
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("INSERT OR IGNORE INTO channel_playlists (channel_id, playlist_id, added_at) VALUES (?, ?, ?)", (channel_id, playlist_id, datetime.now().isoformat()))
            conn.execute("""
                UPDATE channels 
                SET thumbnail_url = (SELECT thumbnail_url FROM playlists WHERE id = ?) 
                WHERE id = ? AND (thumbnail_url IS NULL OR thumbnail_url = '')
            """, (playlist_id, channel_id))

    def update_channel(self, channel_id: int, name: str):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("UPDATE channels SET name = ? WHERE id = ?", (name, channel_id))

    def delete_channel(self, channel_id: int):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("DELETE FROM channels WHERE id = ?", (channel_id,))

    def get_channel_playlists(self, channel_id: int) -> List[Dict[str, Any]]:
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute("""
                SELECT p.*, (SELECT COUNT(*) FROM playlist_items WHERE playlist_id = p.id) as item_count 
                FROM playlists p 
                JOIN channel_playlists cp ON p.id = cp.playlist_id 
                WHERE cp.channel_id = ? 
                ORDER BY p.created_at DESC
            """, (channel_id,)).fetchall()
            return [dict(r) for r in rows]

    def remove_playlist_from_channel(self, channel_id: int, playlist_id: int):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("DELETE FROM channel_playlists WHERE channel_id = ? AND playlist_id = ?", (channel_id, playlist_id))
