#!/bin/zsh
# Downloads the ready-made Tidywise app and puts it in ~/Applications. Nothing is built.
#
#   curl -fsSL https://raw.githubusercontent.com/floorianmb/tidywise/main/get-tidywise.sh | zsh
#
# You still need Python 3.12+ and Ollama on the Mac; the app tells you when one is missing.
set -euo pipefail

URL="https://github.com/floorianmb/tidywise/releases/latest/download/Tidywise.zip"
DEST="$HOME/Applications"

[[ "$(uname)" == "Darwin" ]] || { print "Tidywise only runs on macOS." >&2; exit 1; }
[[ "$(uname -m)" == "arm64" ]] || { print "The download is built for Apple silicon. On an Intel Mac, build from source: see the README." >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
print "→ Downloading Tidywise"
curl -fL --progress-bar "$URL" -o "$TMP/Tidywise.zip"
print "→ Installing to ~/Applications"
mkdir -p "$DEST"
pkill -x Tidywise 2>/dev/null && sleep 1 || true
rm -rf "$DEST/Tidywise.app"
ditto -x -k "$TMP/Tidywise.zip" "$DEST"
open "$DEST/Tidywise.app"
print "✓ Tidywise is open and walks you through setup."
