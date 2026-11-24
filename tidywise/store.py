from __future__ import annotations

import json
import sqlite3
from datetime import datetime
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS files(
    id INTEGER PRIMARY KEY,
    orig_path TEXT NOT NULL,
    cur_path TEXT,
    name TEXT NOT NULL,
    ext TEXT,
    size INTEGER,
    mtime REAL,
    topic TEXT,
    new_topic TEXT,
    summary TEXT,
    keywords TEXT,
    source_url TEXT,
    confidence REAL,
    status TEXT NOT NULL,          -- planned | moved | undone
    classified_at TEXT,
    moved_at TEXT
);
CREATE INDEX IF NOT EXISTS files_orig ON files(orig_path, status);
CREATE TABLE IF NOT EXISTS links(
    url TEXT PRIMARY KEY,
    title TEXT,
    domain TEXT,
    topic TEXT,
    first_visit TEXT,
    last_visit TEXT,
    visits INTEGER
);
CREATE TABLE IF NOT EXISTS searches(
    term TEXT NOT NULL,
    at TEXT NOT NULL,
    PRIMARY KEY(term, at)
);
CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
"""


def now_iso() -> str:
    return datetime.now().isoformat(timespec="seconds")


class Store:
    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(path, timeout=60)
        self.db.row_factory = sqlite3.Row
        self.db.executescript(SCHEMA)
        self.log_path = path.with_name("moves.jsonl")

    def commit(self) -> None:
        self.db.commit()

    # meta
    def get_meta(self, key: str, default: str | None = None) -> str | None:
        row = self.db.execute("SELECT value FROM meta WHERE key=?", (key,)).fetchone()
        return row["value"] if row else default

    def set_meta(self, key: str, value: str) -> None:
        self.db.execute("INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, value))

    # files
    def planned_for(self, orig_path: str) -> sqlite3.Row | None:
        return self.db.execute(
            "SELECT * FROM files WHERE orig_path=? AND status='planned' ORDER BY id DESC LIMIT 1", (orig_path,)
        ).fetchone()

    def drop_planned(self, orig_path: str | None = None) -> None:
        if orig_path is None:
            self.db.execute("DELETE FROM files WHERE status='planned'")
        else:
            self.db.execute("DELETE FROM files WHERE status='planned' AND orig_path=?", (orig_path,))

    def add_planned(self, **f) -> int:
        f.setdefault("status", "planned")
        f.setdefault("classified_at", now_iso())
        if isinstance(f.get("keywords"), list):
            f["keywords"] = ", ".join(f["keywords"])
        cols = ",".join(f)
        cur = self.db.execute(f"INSERT INTO files({cols}) VALUES({','.join('?' * len(f))})", tuple(f.values()))
        return cur.lastrowid

    def planned(self) -> list[sqlite3.Row]:
        return self.db.execute("SELECT * FROM files WHERE status='planned' ORDER BY id").fetchall()

    def moved(self) -> list[sqlite3.Row]:
        return self.db.execute("SELECT * FROM files WHERE status='moved' ORDER BY moved_at, id").fetchall()

    def get_file(self, file_id: int) -> sqlite3.Row | None:
        return self.db.execute("SELECT * FROM files WHERE id=?", (file_id,)).fetchone()

    def update_file(self, file_id: int, **f) -> None:
        sets = ",".join(f"{k}=?" for k in f)
        self.db.execute(f"UPDATE files SET {sets} WHERE id=?", (*f.values(), file_id))

    def log_move(self, action: str, file_id: int, src: str, dst: str) -> None:
        with open(self.log_path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"at": now_iso(), "action": action, "id": file_id, "src": src, "dst": dst}, ensure_ascii=False) + "\n")

    # links
    def link(self, url: str) -> sqlite3.Row | None:
        return self.db.execute("SELECT * FROM links WHERE url=?", (url,)).fetchone()

    def upsert_link(self, url: str, title: str, domain: str, topic: str | None, first: str, last: str, visits: int) -> None:
        self.db.execute(
            """INSERT INTO links(url,title,domain,topic,first_visit,last_visit,visits) VALUES(?,?,?,?,?,?,?)
               ON CONFLICT(url) DO UPDATE SET title=excluded.title, last_visit=max(last_visit, excluded.last_visit),
               visits=visits+excluded.visits, topic=coalesce(links.topic, excluded.topic)""",
            (url, title, domain, topic, first, last, visits),
        )

    def add_search(self, term: str, at: str) -> None:
        self.db.execute("INSERT OR IGNORE INTO searches(term, at) VALUES(?,?)", (term, at))
