"""Creates made-up sample data – for screenshots and for trying things out without touching real files.

    .venv/bin/python scripts/demo.py /tmp/wissen-demo
    WISSEN_CONFIG=/tmp/wissen-demo/config.toml WISSEN_STATE_DIR=/tmp/wissen-demo/state \\
        app/build/Wissen.app/Contents/MacOS/Wissen --snapshot /tmp/wissen-demo/pictures

The app and the CLI then read only from that folder. Nothing is moved; the "files" exist only
as entries in the database.
"""
from __future__ import annotations

import dataclasses
import random
import sqlite3
import sys
from datetime import datetime, timedelta
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO))

from wissen import config, telemetry  # noqa: E402
from wissen.store import Store  # noqa: E402

FILES = [
    # (name, topic, summary, keywords, confidence, folder, sorted … hours ago | None = suggestion)
    ("Invoice_City_Utilities_2026-10.pdf", "finance", "Electricity bill from City Utilities for October 2026 with instalment and meter reading.", "electricity, invoice, utilities, instalment", 0.95, "Downloads", 3),
    ("Bank_statement_September.pdf", "finance", "Statement of the current account for September 2026.", "bank statement, current account, bank", 0.93, "Downloads", 30),
    ("Lease_Linden_Street.pdf", "personal-documents", "Signed lease for the flat on Linden Street.", "lease, flat, landlord", 0.91, "Documents", 50),
    ("Resume_2026.docx", "personal-documents", "Current résumé with work experience and education.", "résumé, application, CV", 0.96, "Desktop", 75),
    ("Lecture_07_Statistics.pdf", "study", "Slides of the seventh statistics lecture on confidence intervals.", "statistics, lecture, confidence interval", 0.94, "Downloads", 5),
    ("Term_paper_draft_v3.docx", "study", "Third draft of the term paper on urban planning in the 20th century.", "term paper, urban planning, draft", 0.88, "Desktop", 26),
    ("Quarterly_report_Q3.pptx", "work", "Presentation with the third-quarter figures for the team meeting.", "quarterly report, figures, presentation", 0.9, "Downloads", 8),
    ("Minutes_weekly_sync_W45.md", "work", "Minutes of the weekly sync with a task list.", "minutes, weekly sync, tasks", 0.86, "Documents", 100),
    ("Train_ticket_Hamburg_Munich.pdf", "travel", "Online train ticket for the journey from Hamburg to Munich.", "train, ticket, Hamburg, Munich", 0.97, "Downloads", 12),
    ("Hotel_confirmation_Lisbon.pdf", "travel", "Booking confirmation for three nights at a hotel in Lisbon.", "hotel, Lisbon, booking", 0.95, "Downloads", 140),
    ("IMG_4821.heic", "photos-and-media", "Photo of a coastal landscape at sunset.", "photo, coast, sunset", 0.82, "Desktop", 20),
    ("Screenshot 2026-11-20 at 09.14.png", "photos-and-media", "Screenshot of a table of monthly expenses.", "screenshot, table, expenses", 0.71, "Desktop", 60),
    ("Blender-4.4-macos-arm64.dmg", "software", "Installer for the 3D program Blender.", "Blender, installer, 3D", 0.98, "Downloads", 44),
    ("api_client.py", "ai-and-development", "Python script that queries a REST API and saves the response.", "Python, API, script", 0.89, "Downloads", 2),
    ("Demo_song_mix2.wav", "music-and-audio", "Second mix of a self-recorded song.", "audio, mix, song", 0.84, "Desktop", 170),
    ("Order_headphones.pdf", "shopping", "Order confirmation for Bluetooth headphones.", "order, headphones, confirmation", 0.87, "Downloads", 90),
    ("Scan_0042.pdf", "other", "Scanned document without recognisable text.", "scan, unclear", 0.35, "Downloads", 15),  # → inbox
    # suggestions
    ("Service_charges_2025.pdf", "finance", "Annual statement of service charges for 2025 with an additional payment.", "service charges, statement, flat", 0.92, "Downloads", None),
    ("Seminar_schedule_winter.pdf", "study", "Schedule of the seminar in the winter semester 2026/27.", "seminar, dates, winter semester", 0.9, "Downloads", None),
    ("Flight_LIS_boarding_pass.pdf", "travel", "Boarding pass for the flight to Lisbon.", "flight, boarding pass, Lisbon", 0.96, "Desktop", None),
    ("notes.txt", "other", "Short, unsorted notes without a clear topic.", "notes", 0.4, "Desktop", None),
]

LINKS = [
    ("Confidence interval – Wikipedia", "en.wikipedia.org", "study"),
    ("Statistics lecture notes, chapter 7", "university-example.edu", "study"),
    ("Python requests: Quickstart", "requests.readthedocs.io", "ai-and-development"),
    ("Ollama – run models locally", "ollama.com", "ai-and-development"),
    ("SwiftUI Tutorials", "developer.apple.com", "ai-and-development"),
    ("Lisbon: 12 tips for three days", "travelblog-example.com", "travel"),
    ("Trains: Hamburg – Munich", "bahn.de", "travel"),
    ("Headphones compared 2026", "reviews-example.com", "shopping"),
    ("Compare electricity tariffs", "compare-example.com", "accounts-and-contracts"),
    ("Checking your service charge statement", "tenants-example.org", "finance"),
    ("Blender 4.4 Release Notes", "blender.org", "software"),
    ("Mixing basics: EQ and compressor", "studio-example.com", "music-and-audio"),
    ("Chess openings for beginners", "lichess.org", "games"),
    ("The best podcasts this autumn", "magazine-example.com", "social-and-entertainment"),
]

SEARCHES = ["calculate confidence interval", "lisbon sights", "service charge statement deadline",
            "python write json file", "noise cancelling headphones review"]


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    base = Path(sys.argv[1]).expanduser().resolve()
    state = base / "state"
    if (state / "wissen.sqlite").exists():
        (state / "wissen.sqlite").unlink()
    home = Path.home()

    raw = config.to_dict(config.load(config.DEFAULT_CONFIG))
    raw["root"] = "~/Wissen"  # a destination that doesn't exist yet, so the demo shows a fresh install
    raw["links_enabled"] = True
    cfg = config.save(raw, base / "config.toml")
    cfg = dataclasses.replace(cfg, state_dir=state)

    random.seed(7)
    now = datetime.now()
    store = Store(cfg.db_path)
    for name, topic, summary, keywords, conf, folder, hours in FILES:
        orig = home / folder / name
        file_id = store.add_planned(
            orig_path=str(orig), name=name, ext=Path(name).suffix.lower(), size=random.randint(40_000, 4_000_000),
            mtime=(now - timedelta(days=random.randint(1, 60))).timestamp(), topic=topic, new_topic=None, summary=summary,
            keywords=keywords.split(", "), source_url=None, confidence=conf,
            classified_at=(now - timedelta(hours=(hours or 0) + 1)).isoformat(timespec="seconds"),
        )
        if hours is not None:
            dest = (cfg.topics_dir / topic if conf >= cfg.min_confidence else cfg.inbox_dir) / name
            store.update_file(file_id, cur_path=str(dest), status="moved",
                              moved_at=(now - timedelta(hours=hours)).isoformat(timespec="seconds"))
    for i, (title, domain, topic) in enumerate(LINKS):
        at = (now - timedelta(hours=3 + i * 7)).isoformat(timespec="seconds")
        store.upsert_link(f"https://{domain}/beispiel-{i}", title, domain, topic, at, at, random.randint(1, 6))
    for i, term in enumerate(SEARCHES):
        store.add_search(term, (now - timedelta(hours=4 + i * 9)).isoformat(timespec="seconds"))
    store.set_meta("agent_last_run", (now - timedelta(minutes=6)).isoformat(timespec="seconds"))
    store.set_meta("chrome_last_run", (now - timedelta(minutes=6)).isoformat(timespec="seconds"))
    store.commit()

    # A few model calls so that "AI speed" has something to show
    for i in range(40):
        tokens = random.randint(60, 110)
        tps = random.uniform(38, 52)
        telemetry.record_call(cfg, "file" if i % 3 else "links", FILES[i % len(FILES)][0] if i % 3 else "40 pages", {
            "prompt_eval_count": random.randint(700, 1500), "eval_count": tokens,
            "prompt_eval_duration": random.uniform(0.4, 0.9) * 1e9, "eval_duration": tokens / tps * 1e9,
            "load_duration": 0, "total_duration": (tokens / tps + random.uniform(0.6, 1.2)) * 1e9,
        }, images=0)
    con = sqlite3.connect(cfg.db_path)  # spread the calls over the last two hours
    for (call_id,) in con.execute("SELECT id FROM llm_calls").fetchall():
        con.execute("UPDATE llm_calls SET at=? WHERE id=?",
                    ((now - timedelta(minutes=(40 - call_id) * 3)).isoformat(timespec="seconds"), call_id))
    con.commit()
    con.close()
    print(f"Sample data in {base}\n"
          f"  WISSEN_CONFIG={base / 'config.toml'} WISSEN_STATE_DIR={state}")


if __name__ == "__main__":
    main()
