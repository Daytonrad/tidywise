#!/usr/bin/env python3
"""Benchmark for link classification: compare quality and speed of different variants.

Reference:
  ~/Library/Application Support/tidywise/bench/links_gold.jsonl  – real links, classified blind by hand
      (stays local, not in the repo). Each line: title, domain, ok (list of allowed topics), split (dev|test)
  bench/links_edge_cases.jsonl – made-up edge cases (in the repo), using the slugs of the default topics

Against overfitting: compare variants on `dev` only. Use `test` once, at the very end, for the final choice.

Examples:
  .venv/bin/python scripts/bench_links.py                         # current state on dev + edge cases
  .venv/bin/python scripts/bench_links.py --fmt keyed --batch 40 --parallel 2 --repeat 2
  .venv/bin/python scripts/bench_links.py --split test --fmt keyed --errors
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO))

from tidywise import chrome  # noqa: E402
from tidywise.__main__ import run_lock  # noqa: E402
from tidywise.config import load  # noqa: E402
from tidywise.store import Store  # noqa: E402


# The edge cases use the English default slugs. A configuration from before the switch to English uses
# German ones – accept those as the same topic so the edge cases stay usable there.
LEGACY_SLUGS = {
    "accounts-and-contracts": "alltag-und-konten", "work": "arbeit", "finance": "finanzen",
    "photos-and-media": "fotos-und-medien", "ai-and-development": "ki-und-entwicklung", "music-and-audio": "musik-audio",
    "personal-documents": "persoenliche-dokumente", "travel": "reisen",
    "social-and-entertainment": "social-und-unterhaltung", "other": "sonstiges", "study": "studium",
}


def load_sets(cfg, split: str, edges: bool) -> list[dict]:
    rows: list[dict] = []
    gold = cfg.state_dir / "bench" / "links_gold.jsonl"
    if gold.exists():
        for line in gold.read_text().splitlines():
            r = json.loads(line)
            if split == "all" or r["split"] == split:
                rows.append({**r, "set": r["split"]})
    else:
        print(f"Note: {gold} is missing – edge cases only.", file=sys.stderr)
    if edges:
        for line in (REPO / "bench" / "links_edge_cases.jsonl").read_text().splitlines():
            r = json.loads(line)
            ok = r["ok"] + [LEGACY_SLUGS[s] for s in r["ok"] if s in LEGACY_SLUGS]
            if "work" in r["ok"]:  # any work topic of an older German configuration, e.g. "arbeit-firma"
                ok += [s for s in cfg.slugs if s.startswith("arbeit")]
            rows.append({**r, "ok": ok, "set": "edge"})
    return rows


def run_once(cfg, rows, fmt: str, batch: int, parallel: int) -> tuple[list[str], float]:
    pairs = [(r["title"], r["domain"]) for r in rows]
    chunks = [pairs[i:i + batch] for i in range(0, len(pairs), batch)]
    t0 = time.perf_counter()
    with ThreadPoolExecutor(max_workers=parallel) as ex:
        results = list(ex.map(lambda c: chrome._classify(cfg, c, fmt=fmt, kind="bench"), chunks))
    return [t for chunk in results for t in chunk], time.perf_counter() - t0


def score(rows, preds) -> dict[str, tuple[int, int]]:
    out: dict[str, list[int]] = {}
    for r, p in zip(rows, preds):
        s = out.setdefault(r["set"], [0, 0])
        s[0] += p in r["ok"]
        s[1] += 1
    return {k: (v[0], v[1]) for k, v in out.items()}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--split", default="dev", choices=["dev", "test", "all"])
    ap.add_argument("--no-edge", action="store_true", help="leave out the edge cases")
    ap.add_argument("--fmt", default=chrome.FORMAT, choices=chrome.FORMATS)
    ap.add_argument("--batch", type=int, default=40)
    ap.add_argument("--parallel", type=int, default=1)
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--errors", action="store_true", help="show wrong classifications")
    args = ap.parse_args()

    cfg = load()
    rows = load_sets(cfg, args.split, not args.no_edge)
    lock = run_lock(cfg, wait=True)  # pause background runs so the timings are right
    store = Store(cfg.db_path)
    chrome._classify(cfg, [("Warmup", "example.com")], fmt=args.fmt, kind="bench")  # load the model

    for rep in range(args.repeat):
        since = datetime.now().isoformat(timespec="seconds")
        preds, secs = run_once(cfg, rows, args.fmt, args.batch, args.parallel)
        tok = store.db.execute(
            "SELECT COALESCE(SUM(output_tokens),0), COALESCE(SUM(prompt_tokens),0), COUNT(*), SUM(ok=0) "
            "FROM llm_calls WHERE kind='bench' AND at >= ?", (since,)).fetchone()
        sc = score(rows, preds)
        right = sum(v[0] for v in sc.values())
        parts = "  ".join(f"{k} {a}/{n} ({a / n:.1%})" for k, (a, n) in sorted(sc.items()))
        print(f"{args.fmt:<12} batch {args.batch:<3} parallel {args.parallel}  |  {parts}  |  total {right / len(rows):.1%}"
              f"  |  {secs:5.1f} s = {len(rows) / secs:4.1f} Links/s  |  {tok[0] / len(rows):.1f} output tokens/link"
              f"{'  | errors: ' + str(tok[3]) if tok[3] else ''}", flush=True)
        results_path = cfg.state_dir / "bench" / "results.jsonl"
        results_path.parent.mkdir(parents=True, exist_ok=True)
        with open(results_path, "a") as f:
            f.write(json.dumps({"at": since, "split": args.split, "fmt": args.fmt, "batch": args.batch,
                                "parallel": args.parallel, "score": sc, "seconds": secs,
                                "out_tokens": tok[0], "prompt_tokens": tok[1], "calls": tok[2],
                                "preds": preds}) + "\n")
        if args.errors and rep == args.repeat - 1:
            for r, p in zip(rows, preds):
                if p not in r["ok"]:
                    print(f"  [{r['set']}] {r['title'][:70]!r} | {r['domain']}  →  {p}   (allowed: {', '.join(r['ok'])})")
    lock.close()


if __name__ == "__main__":
    main()
