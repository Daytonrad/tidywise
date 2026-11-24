#!/bin/zsh
# Removes Tidywise from this Mac: background service, app, command line and skill link.
# Your sorted files, the settings and the database stay – the end of the output says where they are.
set -uo pipefail
REPO="${0:A:h}"

pkill -x Tidywise 2>/dev/null
[[ -x "$REPO/.venv/bin/tidywise" ]] && "$REPO/.venv/bin/tidywise" service uninstall >/dev/null 2>&1
PLIST="$HOME/Library/LaunchAgents/local.tidywise.agent.plist"
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null
rm -f "$PLIST" "$HOME/.local/bin/tidywise"
rm -rf "$HOME/Applications/Tidywise.app"
[[ -L "$HOME/.claude/skills/tidywise" ]] && rm "$HOME/.claude/skills/tidywise"

print "Removed: service, app, command line."
print "Still there (delete yourself if you want):"
print "  your sorted files             (destination folder, default: ~/Downloads/Tidywise)"
print "  ~/.config/tidywise              settings"
print "  ~/Library/Application Support/tidywise   database and move log"
print "  ~/Library/Logs/tidywise         log"
print "  the AI model                  ollama rm <model>"
