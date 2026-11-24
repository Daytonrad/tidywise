#!/bin/zsh
# Removes Wissen from this Mac: background service, app, command line and skill link.
# Your sorted files, the settings and the database stay – the end of the output says where they are.
set -uo pipefail
REPO="${0:A:h}"

pkill -x Wissen 2>/dev/null
[[ -x "$REPO/.venv/bin/wissen" ]] && "$REPO/.venv/bin/wissen" service uninstall >/dev/null 2>&1
PLIST="$HOME/Library/LaunchAgents/local.wissen.agent.plist"
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null
rm -f "$PLIST" "$HOME/.local/bin/wissen"
rm -rf "$HOME/Applications/Wissen.app"
[[ -L "$HOME/.claude/skills/wissen" ]] && rm "$HOME/.claude/skills/wissen"

print "Removed: service, app, command line."
print "Still there (delete yourself if you want):"
print "  your sorted files             (destination folder, default: ~/Downloads/Wissen)"
print "  ~/.config/wissen              settings"
print "  ~/Library/Application Support/wissen   database and move log"
print "  ~/Library/Logs/wissen         log"
print "  the AI model                  ollama rm <model>"
