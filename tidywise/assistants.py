"""Connecting AI assistants to the MCP server (`tidywise mcp`): Claude Code, Codex, OpenCode – and a
copy-and-paste configuration for everything else.

Each assistant is registered through its own command line where that exists, so Tidywise never has to know
the format of someone else's settings file. Supporting another assistant = adding an entry to CLIENTS.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path

NAME = "tidywise"
HOME = Path.home()
# Where command-line tools usually live when they are not on the PATH of a Mac app.
SEARCH_PATH = [HOME / ".local/bin", Path("/opt/homebrew/bin"), Path("/usr/local/bin"), HOME / ".opencode/bin",
               HOME / ".npm-global/bin", HOME / ".bun/bin", HOME / ".cargo/bin", HOME / ".claude/local"]


class AssistantError(RuntimeError):
    """Connecting did not work. The text is written for people and shown in the app."""


def server_command() -> list[str]:
    """The command an assistant runs to start the server: a stable path to `tidywise`, plus `mcp`."""
    for candidate in (os.environ.get("TIDYWISE_CLI"), str(HOME / ".local/bin/tidywise"), shutil.which("tidywise"),
                      str(Path(sys.argv[0]).resolve())):
        if candidate and os.access(candidate, os.X_OK):
            return [candidate, "mcp"]
    return ["tidywise", "mcp"]


def _find(binary: str) -> str | None:
    path = os.pathsep.join([os.environ.get("PATH", "")] + [str(p) for p in SEARCH_PATH])
    return shutil.which(binary, path=path)


def _run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL)


def _json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


@dataclass(frozen=True)
class Client:
    id: str
    title: str
    binary: str

    @property
    def path(self) -> str | None:
        return _find(self.binary)

    @property
    def installed(self) -> bool:
        return self.path is not None

    def connected(self) -> bool:
        raise NotImplementedError

    def add_args(self, cli: str, command: list[str]) -> list[str]:
        raise NotImplementedError

    def remove(self, cli: str) -> None:
        raise NotImplementedError


class ClaudeCode(Client):
    def connected(self) -> bool:
        return NAME in (_json(HOME / ".claude.json").get("mcpServers") or {})

    def add_args(self, cli: str, command: list[str]) -> list[str]:
        return [cli, "mcp", "add", "--scope", "user", NAME, "--", *command]

    def remove(self, cli: str) -> None:
        r = _run([cli, "mcp", "remove", "--scope", "user", NAME])
        if r.returncode != 0:
            raise AssistantError(f"{self.title} could not remove the server: {(r.stderr or r.stdout).strip()[:300]}")


class Codex(Client):
    config = HOME / ".codex/config.toml"

    def connected(self) -> bool:
        try:
            return NAME in (tomllib.loads(self.config.read_text()).get("mcp_servers") or {})
        except (OSError, ValueError):
            return False

    def add_args(self, cli: str, command: list[str]) -> list[str]:
        return [cli, "mcp", "add", NAME, "--", *command]

    def remove(self, cli: str) -> None:
        r = _run([cli, "mcp", "remove", NAME])
        if r.returncode != 0:
            raise AssistantError(f"{self.title} could not remove the server: {(r.stderr or r.stdout).strip()[:300]}")


def _strip_jsonc_comments(text: str) -> str:
    """Remove // and /* */ comments outside string literals so JSONC can be inspected safely."""
    pattern = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/', re.DOTALL)
    return pattern.sub(lambda m: m.group(0) if m.group(0).startswith('"') else "", text)


class OpenCode(Client):
    configs = [HOME / ".config/opencode/opencode.json", HOME / ".config/opencode/opencode.jsonc"]

    def _servers(self, data: dict) -> dict:
        mcp = data.get("mcp") or {}
        return mcp.get("servers") if isinstance(mcp.get("servers"), dict) else mcp  # newer and older layout

    def _matched_config(self) -> Path | None:
        for p in self.configs:
            data = _json(p)
            if data:
                if NAME in self._servers(data):
                    return p
            else:
                stripped = _strip_jsonc_comments(_text(p))
                try:
                    parsed = json.loads(re.sub(r",(\s*[}\]])", r"\1", stripped)) if stripped.strip() else {}
                except ValueError:
                    parsed = None
                if isinstance(parsed, dict):
                    if NAME in self._servers(parsed):
                        return p
                elif f'"{NAME}"' in stripped:
                    return p
        return None

    def connected(self) -> bool:
        return self._matched_config() is not None

    def add_args(self, cli: str, command: list[str]) -> list[str]:
        return [cli, "mcp", "add", "--global", NAME, "--", *command]

    def remove(self, cli: str) -> None:
        # OpenCode has no command for this; its settings file is plain JSON we can edit safely.
        for p in self.configs:
            data = _json(p)
            servers = self._servers(data) if data else {}
            if NAME in servers:
                del servers[NAME]
                p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
                return
        if (matched := self._matched_config()) is not None:
            raise AssistantError(f"Please remove “{NAME}” from the “mcp” section of {matched} by hand.")


def _text(path: Path) -> str:
    try:
        return path.read_text()
    except OSError:
        return ""


CLIENTS: list[Client] = [
    ClaudeCode("claude", "Claude Code", "claude"),
    Codex("codex", "Codex", "codex"),
    OpenCode("opencode", "OpenCode", "opencode"),
]


def client(client_id: str) -> Client:
    for c in CLIENTS:
        if c.id == client_id:
            return c
    raise AssistantError(f"Unknown assistant “{client_id}”. Available: {', '.join(c.id for c in CLIENTS)}")


def connect(client_id: str) -> str:
    """Register the server with an assistant. Returns a sentence saying what happened."""
    c = client(client_id)
    cli = c.path
    if cli is None:
        raise AssistantError(f"{c.title} was not found on this Mac. Install it first, or use the manual configuration.")
    if c.connected():
        c.remove(cli)  # replace an older entry, e.g. after Tidywise moved
    r = _run(c.add_args(cli, server_command()))
    if r.returncode != 0:
        raise AssistantError(f"{c.title} did not accept the server: {(r.stderr or r.stdout).strip()[:300]}")
    return f"{c.title} can now search your archive. Start a new session there to use it."


def disconnect(client_id: str) -> str:
    c = client(client_id)
    cli = c.path
    if cli is None:
        raise AssistantError(f"{c.title} was not found on this Mac.")
    c.remove(cli)
    return f"Removed from {c.title}."


def manual_snippet() -> str:
    """The configuration most other assistants understand (the common `mcpServers` format)."""
    command = server_command()
    return json.dumps({"mcpServers": {NAME: {"command": command[0], "args": command[1:]}}}, indent=2)


def status() -> dict:
    """Everything the app needs to draw its “Assistants” page."""
    command = server_command()
    return {
        "command": command,
        "command_line": " ".join(command),
        "snippet": manual_snippet(),
        "clients": [{"id": c.id, "title": c.title, "installed": c.installed, "connected": c.connected()} for c in CLIENTS],
    }
