"""Generate Markdown files from the database: AGENTS.md, Topics/*/_index.md, Links/*.md, Days/*.md."""
from __future__ import annotations

import os
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path
from urllib.parse import quote

from .config import Config
from .store import Store

RECENT_DAYS = 14
LINKS_PER_TOPIC_PER_DAY = 8


def _write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or path.read_text(encoding="utf-8") != text:
        path.write_text(text, encoding="utf-8")


def _rel(cfg: Config, p: str | Path) -> str:
    try:
        return quote(str(Path(p).relative_to(cfg.root)))
    except ValueError:
        return quote(str(p))


def _md(s: str | None) -> str:
    return (s or "").replace("|", "/").replace("\n", " ").strip()


def _day(iso: str | None) -> str:
    return (iso or "")[:10]


def render(cfg: Config, store: Store) -> None:
    cfg.ensure_dirs()
    db = store.db
    moved = db.execute("SELECT * FROM files WHERE status='moved' ORDER BY moved_at DESC").fetchall()
    links = db.execute("SELECT * FROM links WHERE topic IS NOT NULL ORDER BY last_visit DESC").fetchall()
    searches = db.execute("SELECT * FROM searches ORDER BY at DESC").fetchall()
    names = {t.slug: t.name for t in cfg.topics}
    links_name = cfg.links_dir.name  # folder names as they are on disk (older installs keep Themen/, Tage/, _privat/)

    files_by_topic = defaultdict(list)
    for r in moved:
        key = "_inbox" if Path(r["cur_path"]).parent.name == "_inbox" else r["topic"]
        files_by_topic[key].append(r)
    links_by_topic = defaultdict(list)
    for r in links:
        links_by_topic[r["topic"]].append(r)

    # Topics/<slug>/_index.md
    for t in cfg.topics:
        rows = files_by_topic.get(t.slug, [])
        lines = [f"# {t.name}", "", f"_{t.description}_", "",
                 f"Links on this topic: [{links_name}/{t.slug}.md](../../{links_name}/{t.slug}.md) ({len(links_by_topic.get(t.slug, []))})", ""]
        if rows:
            lines += ["| Date | File | What it's about | Keywords | Source |", "|---|---|---|---|---|"]
            for r in rows:
                src = f"[Link]({r['source_url']})" if r["source_url"] else ""
                link = quote(os.path.relpath(r["cur_path"], cfg.topics_dir / t.slug))  # also from year subfolders
                lines.append(f"| {_day(r['moved_at'])} | [{_md(r['name'])}]({link}) | "
                             f"{_md(r['summary'])} | {_md(r['keywords'])} | {src} |")
        else:
            lines.append("_No files yet._")
        _write(cfg.topics_dir / t.slug / "_index.md", "\n".join(lines) + "\n")

    # _inbox/_index.md
    rows = files_by_topic.get("_inbox", [])
    lines = ["# Inbox – unsure classification", "",
             "Sort properly with `tidywise set <no.> <topic>`.", "",
             "| No. | File | Suggestion | Confidence | What it's about |", "|---|---|---|---|---|"]
    for r in rows:
        suggestion = r["new_topic"] and f"new: {r['new_topic']}" or r["topic"]
        lines.append(f"| {r['id']} | [{_md(r['name'])}]({quote(r['name'])}) | {_md(suggestion)} | "
                     f"{(r['confidence'] or 0):.1f} | {_md(r['summary'])} |")
    _write(cfg.inbox_dir / "_index.md", "\n".join(lines) + "\n")

    # Links/<slug>.md
    for slug, rows in links_by_topic.items():
        lines = [f"# Links: {names.get(slug, slug)}", ""]
        month = None
        for r in rows:
            m = _day(r["last_visit"])[:7]
            if m != month:
                lines += ["", f"## {m}"]
                month = m
            visits = f" ({r['visits']}×)" if (r["visits"] or 0) > 1 else ""
            lines.append(f"- {_day(r['last_visit'])} [{_md(r['title'])}]({r['url']}) – {r['domain']}{visits}")
        _write(cfg.links_dir / f"{slug}.md", "\n".join(lines) + "\n")

    # Days/YYYY-MM-DD.md
    by_day_files = defaultdict(list)
    for r in moved:
        by_day_files[_day(r["moved_at"])].append(r)
    by_day_links = defaultdict(list)
    for r in links:
        by_day_links[_day(r["last_visit"])].append(r)
    by_day_search = defaultdict(list)
    for r in searches:
        by_day_search[_day(r["at"])].append(r["term"])
    for day in set(by_day_files) | set(by_day_links) | set(by_day_search):
        lines = [f"# {day}", ""]
        if by_day_files.get(day):
            lines.append("## Files sorted")
            for r in by_day_files[day]:
                lines.append(f"- [{_md(r['name'])}](../{_rel(cfg, r['cur_path'])}) – {_md(r['summary'])}")
            lines.append("")
        if by_day_search.get(day):
            lines.append("## Searched for")
            lines += [f"- {_md(t)}" for t in dict.fromkeys(by_day_search[day])]
            lines.append("")
        if by_day_links.get(day):
            lines.append("## Read (by topic)")
            grouped = defaultdict(list)
            for r in by_day_links[day]:
                grouped[r["topic"]].append(r)
            for slug, rs in sorted(grouped.items(), key=lambda kv: -len(kv[1])):
                lines.append(f"### {names.get(slug, slug)} ({len(rs)})")
                for r in rs[:LINKS_PER_TOPIC_PER_DAY]:
                    lines.append(f"- [{_md(r['title'])}]({r['url']})")
                if len(rs) > LINKS_PER_TOPIC_PER_DAY:
                    lines.append(f"- … {len(rs) - LINKS_PER_TOPIC_PER_DAY} more in [{links_name}/{slug}.md](../{links_name}/{slug}.md)")
            lines.append("")
        _write(cfg.days_dir / f"{day}.md", "\n".join(lines) + "\n")

    _write(cfg.root / "AGENTS.md", _agents_md(cfg, moved, links, searches, files_by_topic, links_by_topic))


def _agents_md(cfg, moved, links, searches, files_by_topic, links_by_topic) -> str:
    home = str(Path.home())
    topics_name, days_name, links_name = cfg.topics_dir.name, cfg.days_dir.name, cfg.links_dir.name
    inbox_name, private_name = cfg.inbox_dir.name, cfg.private_dir.name
    lines = [
        "# Tidywise – entry point for agents",
        "",
        f"> Generated automatically by `tidywise` on {datetime.now():%Y-%m-%d %H:%M}. Will be overwritten – do not edit by hand.",
        f"> Read only when the user explicitly asks. Never open or search the `{private_name}/` folder.",
        "",
        "## Finding your way around",
        f"- `{topics_name}/<topic>/_index.md` – per file: date, summary, keywords, download source. The files sit next to it.",
        f"- `{links_name}/<topic>.md` – link collection from the Chrome history, by month (only if turned on).",
        f"- `{days_name}/YYYY-MM-DD.md` – what was sorted, searched for and read on that day.",
        f"- `{inbox_name}/_index.md` – files with an unsure classification.",
        f'- Search: `grep -ril "<term>" {str(cfg.root).replace(home, "~")} --include="*.md" --exclude-dir={private_name}`,'
        " then open the hits and the original files selectively.",
        "- Folders (projects, unpacked downloads) are never moved – they stay where they are (see below).",
        "",
        "## Topics",
        "| Topic | Folder | Files | Links | Last active |",
        "|---|---|---|---|---|",
    ]
    for t in cfg.topics:
        fs, ls = files_by_topic.get(t.slug, []), links_by_topic.get(t.slug, [])
        last = max([_day(r["moved_at"]) for r in fs] + [_day(r["last_visit"]) for r in ls] or [""])
        lines.append(f"| {t.name} | [{topics_name}/{t.slug}]({topics_name}/{t.slug}/_index.md) | {len(fs)} | {len(ls)} | {last} |")
    inbox = files_by_topic.get("_inbox", [])
    if inbox:
        lines.append(f"| Inbox (unsure) | [{inbox_name}]({inbox_name}/_index.md) | {len(inbox)} | – | |")

    lines += ["", f"## Last {RECENT_DAYS} days", ""]
    since = (date.today() - timedelta(days=RECENT_DAYS)).isoformat()
    days = sorted({_day(r["moved_at"]) for r in moved} | {_day(r["last_visit"]) for r in links}
                  | {_day(r["at"]) for r in searches}, reverse=True)
    names = {t.slug: t.name for t in cfg.topics}
    for day in [d for d in days if d >= since]:
        fs = [r for r in moved if _day(r["moved_at"]) == day]
        topic_counts = Counter(r["topic"] for r in links if _day(r["last_visit"]) == day)
        n_search = sum(1 for r in searches if _day(r["at"]) == day)
        parts = []
        if fs:
            parts.append(f"{len(fs)} file(s): " + ", ".join(_md(r["name"]) for r in fs[:5]) + (" …" if len(fs) > 5 else ""))
        if topic_counts:
            parts.append("read: " + ", ".join(f"{names.get(s, s)} ({c})" for s, c in topic_counts.most_common(4)))
        if n_search:
            parts.append(f"{n_search} searches")
        lines.append(f"- [{day}]({days_name}/{day}.md): " + "; ".join(parts))

    lines += ["", "## Folders that stay where they are", ""]
    for folder in cfg.watch:
        try:
            subs = sorted(p.name for p in folder.iterdir()
                          if p.is_dir() and not p.name.startswith(".") and p != cfg.root)
        except OSError:
            continue
        if subs:
            lines.append(f"- `{str(folder).replace(home, '~')}/`: " + ", ".join(f"`{s}`" for s in subs))
    return "\n".join(lines) + "\n"
