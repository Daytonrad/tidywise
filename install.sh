#!/bin/zsh
# Installs Tidywise: the Python part, the command line and the Mac app. The app then walks you through the
# rest (download the AI model, choose folders, topics, automation). Safe to run again, e.g. after `git pull`.
#
#   ./install.sh            everything
#   ./install.sh --no-app   only the `tidywise` command line (no Swift needed)
set -euo pipefail

REPO="${0:A:h}"
VENV="$REPO/.venv"
WITH_APP=1
[[ "${1:-}" == "--no-app" ]] && WITH_APP=0

say()  { print -P "%F{blue}→%f $1"; }
fail() { print -P "%F{red}✗%f $1" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || fail "Tidywise only runs on macOS."

# --- Find Python ≥ 3.12 (the Python that ships with macOS is too old) ------------------------------
PY=""
for cand in python3.15 python3.14 python3.13 python3.12 python3 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
  if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import sys; sys.exit(sys.version_info < (3, 12))' 2>/dev/null; then
    PY="$(command -v "$cand")"; break
  fi
done
[[ -n "$PY" ]] || fail "Python 3.12 or newer is missing. With Homebrew: brew install python"

say "Python part ($("$PY" --version))"
[[ -x "$VENV/bin/python" ]] || "$PY" -m venv "$VENV"
"$VENV/bin/pip" install -q --upgrade pip
PYTHONWARNINGS=ignore "$VENV/bin/pip" install -q -e "$REPO"  # setuptools prints a harmless notice about editable installs

say "Command line: ~/.local/bin/tidywise"
mkdir -p "$HOME/.local/bin"
ln -sf "$VENV/bin/tidywise" "$HOME/.local/bin/tidywise"

# The Claude skill is optional: only link it if Claude Code is used on this Mac.
if [[ -d "$HOME/.claude" ]]; then
  say "Claude skill: ~/.claude/skills/tidywise"
  mkdir -p "$HOME/.claude/skills"
  ln -sfn "$REPO/skill" "$HOME/.claude/skills/tidywise"
fi

# If the background service is already set up, re-install it so it uses the current version.
if launchctl print "gui/$(id -u)/local.tidywise.agent" >/dev/null 2>&1; then
  say "Updating the background service"
  "$VENV/bin/tidywise" service install >/dev/null
fi

if (( WITH_APP )); then
  command -v swift >/dev/null 2>&1 || fail "Swift is missing. Run once: xcode-select --install  (or ./install.sh --no-app)"
  say "Building the Mac app (takes a minute or two the first time)"
  "$REPO/app/build.sh" --install
  print
  print -P "%F{green}✓%f Done. Tidywise is open and walks you through setup."
else
  print
  print -P "%F{green}✓%f Done. Next: tidywise config init && tidywise service install && tidywise scan"
  print "   (You then need Ollama and a model yourself: brew install ollama && ollama pull gemma4:e4b-it-qat)"
fi
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) print "   Tip: ~/.local/bin is not in your PATH – add it to use the \`tidywise\` command in the terminal." ;; esac
