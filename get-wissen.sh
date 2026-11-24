#!/bin/zsh
# Downloads the ready-made Wissen app and puts it in ~/Applications. Nothing is built.
#
#   curl -fsSL https://raw.githubusercontent.com/floorianmb/wissen/main/get-wissen.sh | zsh
#
# You still need Python 3.12+ and Ollama on the Mac; the app tells you when one is missing.
set -euo pipefail

URL="https://github.com/floorianmb/wissen/releases/latest/download/Wissen.zip"
DEST="$HOME/Applications"

[[ "$(uname)" == "Darwin" ]] || { print "Wissen only runs on macOS." >&2; exit 1; }
[[ "$(uname -m)" == "arm64" ]] || { print "The download is built for Apple silicon. On an Intel Mac, build from source: see the README." >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
print "→ Downloading Wissen"
curl -fL --progress-bar "$URL" -o "$TMP/Wissen.zip"
print "→ Installing to ~/Applications"
mkdir -p "$DEST"
pkill -x Wissen 2>/dev/null && sleep 1 || true
rm -rf "$DEST/Wissen.app"
ditto -x -k "$TMP/Wissen.zip" "$DEST"
open "$DEST/Wissen.app"
print "✓ Wissen is open and walks you through setup."
