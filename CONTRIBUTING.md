# Contributing to Tidywise

Thanks for your interest in Tidywise! Bug reports, small fixes, new assistant/browser integrations, and documentation improvements are all welcome.

## Guiding principles

- **Local-first and private:** Nothing leaves the user's Mac (aside from downloading models via Ollama). Never send file contents or metadata to external services.
- **Careful by default:** Never touch folders, projects, `.app` bundles, or `_private/`. Every file move must be logged to `moves.jsonl` and remain undoable.
- **Plain-text & transparent:** Settings live in `config.toml`, indexes are Markdown, and the Mac app drives the same `tidywise` CLI you can run in the terminal.
- **Small, focused PRs:** Keep changes easy to review and aligned with existing code style.

## Local development setup

Requirements: macOS 14+ (Apple silicon), Xcode Command Line Tools (`xcode-select --install`), Python 3.12+, and [Ollama](https://ollama.com/download).

```bash
git clone https://github.com/floorianmb/tidywise.git
cd tidywise
./install.sh
```

Run the test suite:

```bash
.venv/bin/python -m unittest discover tests
```

Build the Mac app without touching your personal files (using demo data):

```bash
app/build.sh
.venv/bin/python scripts/demo.py /tmp/tidywise-demo
TIDYWISE_CONFIG=/tmp/tidywise-demo/config.toml TIDYWISE_STATE_DIR=/tmp/tidywise-demo/state \
  app/build/Tidywise.app/Contents/MacOS/Tidywise
```

## Good places to start

- **New 1-click MCP assistant:** Add a client entry in `CLIENTS` inside `tidywise/assistants.py`.
- **New Ollama model option:** Add an entry in `app/Sources/TidywiseApp/Model/ModelCatalog.swift`.
- **Prompt or link-sorting improvements:** Verify against `scripts/bench_links.py` so accuracy doesn't regress.
- **New MCP tool:** Keep tool schemas compact (low token overhead) and read-only in `tidywise/mcp.py`.

## Opening an issue or PR

- Check existing issues and Discussions before starting larger features.
- Include tests for Python changes (`tests/`) and verify `app/build.sh` compiles cleanly for SwiftUI changes.
