---
name: wissen
description: The user's local knowledge archive (default ~/Downloads/Wissen) – sorted downloads/documents, link collection and searches from the Chrome history, daily logs. Use ONLY when the user explicitly asks you to look on their computer, in their files, downloads or browser history (e.g. "look on my Mac", "get context from my computer", "what did I save/read about X", "/wissen" – in any language, e.g. German "guck mal auf meinem Rechner"). Never load it on your own initiative or as a precaution.
---

# Wissen – getting context from the user's Mac

The archive is maintained by a local background service (`wissen`, a local model through Ollama). You only read it when the user has explicitly asked you to.

**Where is it?** The default is `~/Downloads/Wissen`. The user can change the location – `wissen config` shows it in the `root` line and the folders it looks in under `watch`. Below, `~/Downloads/Wissen` stands for that location.

**Folder names.** New installs use `Topics/`, `Days/` and `_private/`. Installs set up before the project switched to English keep `Themen/`, `Tage/` and `_privat/`. `AGENTS.md` in the archive always names the folders that actually exist – go by that.

## Rules
- Never open, list or search the private folder (`_private/` or `_privat/`). Always exclude it in `grep`/`find`.
- Read only as much as the current question needs. Don't load the whole archive.
- Don't move, delete or rename anything in the archive – unless the user explicitly wants it (then through `wissen set` / `wissen undo`).
- The Markdown files are generated; manual changes are overwritten.

## How to proceed
1. Read `~/Downloads/Wissen/AGENTS.md`: topic overview, the last 14 days, folders that stayed in place.
2. Narrow down to fit the question:
   - Topic known → `~/Downloads/Wissen/Topics/<topic>/_index.md` (file, summary, keywords, source).
   - Time span known ("yesterday", "last week") → `~/Downloads/Wissen/Days/YYYY-MM-DD.md`.
   - Term known → `grep -ril "<term>" ~/Downloads/Wissen --include="*.md" --exclude-dir=_private --exclude-dir=_privat`
   - Web pages read → `~/Downloads/Wissen/Links/<topic>.md`.
3. Only then open the specific original files that look relevant (PDF, code, document). For projects that sit as folders in the watched folders (default: `~/Downloads`, `~/Documents`, `~/Desktop`), look there directly.
4. Briefly tell the user which sources you found and read before you build on them.

## Useful commands
- `wissen status` – state, open suggestions
- `wissen scan` – classify new loose files (suggestions only)
- `wissen links` – read the Chrome history now (only if the user has turned the link collection on)
- `wissen config` – settings: destination folder, watched folders, topics
