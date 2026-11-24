from __future__ import annotations

import json
import urllib.error
import urllib.request

from . import telemetry
from .config import Config


class LLMError(RuntimeError):
    pass


def _post(cfg: Config, path: str, payload: dict, timeout: float) -> dict:
    req = urllib.request.Request(
        cfg.ollama_url + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        raise LLMError(f"Ollama {e.code}: {e.read().decode(errors='replace')[:300]}") from e
    except (urllib.error.URLError, TimeoutError) as e:
        raise LLMError(f"Ollama not reachable at {cfg.ollama_url}: {e}") from e


def available(cfg: Config) -> tuple[bool, str]:
    try:
        with urllib.request.urlopen(cfg.ollama_url + "/api/tags", timeout=5) as resp:
            names = [m["name"] for m in json.loads(resp.read()).get("models", [])]
    except Exception as e:  # noqa: BLE001
        return False, f"Ollama isn't running ({e}). Start it in the Wissen app, or: brew services start ollama"
    wanted = {cfg.model, cfg.model + ":latest"}
    if not wanted & set(names):
        return False, f"Model {cfg.model} is missing. Download it in the Wissen app, or: ollama pull {cfg.model}"
    return True, "ok"


def chat_json(cfg: Config, system: str, user: str, schema: dict, images: list[str] | None = None,
              timeout: float = 300, kind: str = "", label: str = "") -> dict:
    try:
        data = _chat(cfg, system, user, schema, images, timeout)
    except LLMError as e:
        telemetry.record_call(cfg, kind, label, None, len(images or []), error=str(e)[:300])
        raise
    telemetry.record_call(cfg, kind, label, data, len(images or []))
    return _parse(data.get("message", {}).get("content", ""))


def _chat(cfg: Config, system: str, user: str, schema: dict, images: list[str] | None, timeout: float) -> dict:
    msg: dict = {"role": "user", "content": user}
    if images:
        msg["images"] = images
    payload = {
        "model": cfg.model,
        "messages": [{"role": "system", "content": system}, msg],
        "format": schema,
        "stream": False,
        "think": False,  # classifying needs no long reasoning; saves a lot of time
        "keep_alive": "5m",
        "options": {"temperature": 0, "num_ctx": 8192},
    }
    try:
        data = _post(cfg, "/api/chat", payload, timeout)
    except LLMError as e:
        if "structured output" not in str(e):
            raise
        # Some runners (e.g. MLX) can't enforce a schema → put the schema in the prompt and parse the answer ourselves
        payload.pop("format")
        payload["messages"][0]["content"] = (
            system + "\n\nAnswer only with a JSON object matching this schema, with no other text:\n"
            + json.dumps(schema, ensure_ascii=False)
        )
        data = _post(cfg, "/api/chat", payload, timeout)
    return data


def _parse(content: str) -> dict:
    try:
        return json.loads(content)
    except json.JSONDecodeError:
        pass
    start, end = content.find("{"), content.rfind("}")
    if start != -1 and end > start:
        try:
            return json.loads(content[start:end + 1])
        except json.JSONDecodeError:
            pass
    raise LLMError(f"No valid JSON answer: {content[:200]}")
