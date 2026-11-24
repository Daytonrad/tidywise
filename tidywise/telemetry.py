"""What the Mac app displays: statistics per model call (tokens/s) and the current activity."""
from __future__ import annotations

import json
import os
import sqlite3
from datetime import datetime

from .config import Config

SCHEMA = """
CREATE TABLE IF NOT EXISTS llm_calls(
    id INTEGER PRIMARY KEY,
    at TEXT NOT NULL,
    model TEXT,
    kind TEXT,
    label TEXT,
    prompt_tokens INTEGER,
    output_tokens INTEGER,
    prompt_ms REAL,
    eval_ms REAL,
    load_ms REAL,
    total_ms REAL,
    images INTEGER,
    ok INTEGER NOT NULL,
    error TEXT
);
"""


def _now() -> str:
    return datetime.now().isoformat(timespec="seconds")


def record_call(cfg: Config, kind: str, label: str, data: dict | None, images: int = 0, error: str | None = None) -> None:
    ns = lambda k: (data or {}).get(k, 0) / 1e6  # noqa: E731  Ollama reports nanoseconds
    try:
        con = sqlite3.connect(cfg.db_path, timeout=30)
        con.executescript(SCHEMA)
        con.execute(
            """INSERT INTO llm_calls(at, model, kind, label, prompt_tokens, output_tokens, prompt_ms, eval_ms,
                                     load_ms, total_ms, images, ok, error) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (_now(), cfg.model, kind, label[:200], (data or {}).get("prompt_eval_count"), (data or {}).get("eval_count"),
             ns("prompt_eval_duration"), ns("eval_duration"), ns("load_duration"), ns("total_duration"),
             images, 0 if error else 1, error),
        )
        con.commit()
        con.close()
    except sqlite3.Error:
        pass  # statistics must never stop the actual work


def _status_path(cfg: Config):
    return cfg.state_dir / "status.json"


def _write(cfg: Config, payload: dict) -> None:
    path = _status_path(cfg)
    tmp = path.with_suffix(".tmp")
    try:
        tmp.write_text(json.dumps(payload, ensure_ascii=False))
        os.replace(tmp, path)
    except OSError:
        pass


_started: str | None = None


def set_activity(cfg: Config, task: str, label: str = "", done: int | None = None, total: int | None = None) -> None:
    global _started
    _started = _started or _now()
    _write(cfg, {"busy": True, "pid": os.getpid(), "task": task, "label": label, "done": done, "total": total,
                 "started_at": _started, "updated_at": _now()})


def clear_activity(cfg: Config) -> None:
    global _started
    if _started is None:
        return
    _write(cfg, {"busy": False, "pid": None, "last_finished": _now()})
    _started = None
