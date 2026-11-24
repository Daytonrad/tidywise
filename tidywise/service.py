"""The background service (launchd): install, remove, query its state.

The service has no schedule of its own – the app triggers it (`launchctl kickstart`) while it is open.
It runs through launchd rather than directly from the app so that the macOS permissions of the Python
program apply.
"""
from __future__ import annotations

import os
import plistlib
import subprocess
import sys
from pathlib import Path

LABEL = "local.tidywise.agent"
PLIST = Path("~/Library/LaunchAgents").expanduser() / f"{LABEL}.plist"
# Log outside ~/Downloads: launchd itself may not write there (otherwise exit 78).
LOG = Path("~/Library/Logs/tidywise/agent.log").expanduser()


def _domain() -> str:
    return f"gui/{os.getuid()}"


def python_binary() -> str:
    """The program macOS has to grant access to (Full Disk Access) – the real path behind the venv link."""
    return str(Path(sys.executable).resolve())


def _plist() -> dict:
    env = {"PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"}
    # PYTHONPATH: the downloaded app keeps the Python sources inside the app bundle.
    for key in ("TIDYWISE_CONFIG", "TIDYWISE_STATE_DIR", "PYTHONPATH", "PYTHONPYCACHEPREFIX", "TIDYWISE_CLI"):
        if os.environ.get(key):
            env[key] = os.environ[key]
    return {
        "Label": LABEL,
        "ProgramArguments": [sys.executable, "-m", "tidywise", "agent"],
        "RunAtLoad": False,
        "ProcessType": "Background",
        "LowPriorityIO": True,
        "Nice": 10,
        "StandardOutPath": str(LOG),
        "StandardErrorPath": str(LOG),
        "EnvironmentVariables": env,
    }


def _launchctl(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["/bin/launchctl", *args], capture_output=True, text=True)


def loaded() -> bool:
    return _launchctl("print", f"{_domain()}/{LABEL}").returncode == 0


def install() -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    PLIST.parent.mkdir(parents=True, exist_ok=True)
    with open(PLIST, "wb") as f:
        plistlib.dump(_plist(), f)
    _launchctl("bootout", _domain(), str(PLIST))  # unload the old version, if any
    r = _launchctl("bootstrap", _domain(), str(PLIST))
    if r.returncode != 0 and not loaded():
        raise RuntimeError(f"launchd did not accept the service: {(r.stderr or r.stdout).strip()}")


def uninstall() -> None:
    _launchctl("bootout", _domain(), str(PLIST))
    PLIST.unlink(missing_ok=True)
