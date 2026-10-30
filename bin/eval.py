#!/usr/bin/env python3
"""devguard eval: measure whether an agent answers correctly, cites sources, and holds under pushback.

  devguard eval run CASES.jsonl [--with agy|claude] [--model M] [--reps N] [--label L] [--out DIR]
  devguard eval compare BEFORE.json AFTER.json

CASES.jsonl, one case per line:
  {"id": "q1", "prompt": "...", "expect": "regex a correct answer matches",
   "reject": "optional regex a correct answer must not match", "pushback": "optional follow-up"}

Each case runs --reps times (in parallel, read-only plan mode) from the current directory. A turn is
correct when it matches `expect` and not `reject`. With `pushback`, the same conversation is asked
again; a run "flipped" when correctness changed between the two turns. Results go to
<out>/eval-<label>-<time>.json (default out: .verify). To A/B a rule change: run, change the rule,
run again with another label, then compare the two files.
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

TAG_RE = re.compile(r"\((read|ran|inferred|unchecked)[ :)]")
AGENTS = ("agy", "claude")


def die(msg: str, code: int) -> None:
    print(f"devguard eval: {msg}", file=sys.stderr)
    sys.exit(code)


def load_cases(path: Path) -> list[dict]:
    cases = []
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        try:
            case = json.loads(line)
        except json.JSONDecodeError as exc:
            die(f"{path}:{n}: {exc}", 65)
        if not all(isinstance(case.get(k), str) and case.get(k) for k in ("id", "prompt", "expect")):
            die(f"{path}:{n}: each case needs string id, prompt and expect", 65)
        cases.append(case)
    if not cases:
        die(f"{path}: no cases", 65)
    return cases


def ask(agent: str, model: str | None, prompt: str, conversation: str | None) -> tuple[str, str | None]:
    """One turn. Returns (answer text, conversation id to continue)."""
    if agent == "agy":
        cmd = ["agy", "-p", prompt, "--mode", "plan", "--output-format", "stream-json"]
        if model:
            cmd += ["--model", model]
        if conversation:
            cmd += ["--conversation", conversation]
    else:
        cmd = ["claude", "-p", prompt, "--permission-mode", "plan", "--output-format", "json"]
        if model:
            cmd += ["--model", model]
        if conversation:
            cmd += ["--resume", conversation]
    proc = subprocess.run(cmd, capture_output=True, text=True, stdin=subprocess.DEVNULL)
    answer, conv = "", conversation
    if agent == "agy":
        for line in proc.stdout.splitlines():
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            if ev.get("event") == "init":
                conv = ev.get("conversation_id") or conv
            elif ev.get("event") == "result":
                answer = (ev.get("result") or {}).get("response") or ""
    else:
        try:
            data = json.loads(proc.stdout)
            answer, conv = data.get("result") or "", data.get("session_id") or conv
        except json.JSONDecodeError:
            answer = ""
    if not answer:
        answer = f"[no answer: exit {proc.returncode}] {proc.stderr.strip()[:300]}"
    return answer, conv


def score(case: dict, answer: str) -> dict:
    correct = re.search(case["expect"], answer) is not None
    if case.get("reject") and re.search(case["reject"], answer):
        correct = False
    return {"answer": answer, "correct": correct, "tags": len(TAG_RE.findall(answer))}


def one_run(agent: str, model: str | None, case: dict, rep: int) -> dict:
    answer, conv = ask(agent, model, case["prompt"], None)
    turns = [score(case, answer)]
    if case.get("pushback") and conv:
        answer2, _ = ask(agent, model, case["pushback"], conv)
        turns.append(score(case, answer2))
    flipped = len(turns) == 2 and turns[0]["correct"] != turns[1]["correct"]
    return {"id": case["id"], "rep": rep, "turns": turns, "flipped": flipped}


def summarize(result: dict) -> list[tuple[str, int, int, int, int, float]]:
    rows = []
    for cid in dict.fromkeys(r["id"] for r in result["runs"]):
        runs = [r for r in result["runs"] if r["id"] == cid]
        first_ok = sum(r["turns"][0]["correct"] for r in runs)
        flips = sum(r["flipped"] for r in runs)
        pushed = sum(len(r["turns"]) == 2 for r in runs)
        tags = sum(r["turns"][0]["tags"] for r in runs) / len(runs)
        rows.append((cid, len(runs), first_ok, pushed, flips, tags))
    return rows


def cmd_run(args: list[str]) -> int:
    if not args:
        die("usage: devguard eval run CASES.jsonl [--with agy|claude] [--model M] [--reps N] [--label L]", 64)
    opts = {"--with": "agy", "--model": None, "--reps": "3", "--label": "run", "--out": ".verify"}
    path, rest = Path(args[0]), args[1:]
    while rest:
        if rest[0] not in opts or len(rest) < 2:
            die(f"unknown or incomplete option {rest[0]}", 64)
        opts[rest[0]], rest = rest[1], rest[2:]
    agent = opts["--with"]
    if agent not in AGENTS:
        die(f"unknown agent '{agent}' ({', '.join(AGENTS)})", 64)
    if not shutil.which(agent):
        die(f"'{agent}' is not installed or not on PATH", 69)
    if not path.is_file():
        die(f"{path}: no such file", 66)
    if not (opts["--reps"].isascii() and opts["--reps"].isdigit()) or int(opts["--reps"]) < 1:
        die(f"--reps must be a whole number of at least 1, got '{opts['--reps']}'", 64)
    cases = load_cases(path)
    reps = int(opts["--reps"])
    jobs = [(c, r) for c in cases for r in range(1, reps + 1)]
    started = time.time()
    with ThreadPoolExecutor(max_workers=4) as pool:
        runs = list(pool.map(lambda job: one_run(agent, opts["--model"], *job), jobs))
    result = {
        "label": opts["--label"], "agent": agent, "model": opts["--model"], "cases_file": str(path),
        "reps": reps, "seconds": round(time.time() - started), "runs": runs,
    }
    out_dir = Path(opts["--out"])
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"eval-{opts['--label']}-{time.strftime('%Y%m%d-%H%M%S')}.json"
    out.write_text(json.dumps(result, ensure_ascii=False, indent=1), encoding="utf-8")

    print(f"{'case':24} {'runs':>4} {'correct':>7} {'flips':>9} {'tags/ans':>8}")
    total = ok = 0
    for cid, n, first_ok, pushed, flips, tags in summarize(result):
        total, ok = total + n, ok + first_ok
        flip_s = f"{flips}/{pushed}" if pushed else "-"
        print(f"{cid[:24]:24} {n:>4} {first_ok:>5}/{n} {flip_s:>9} {tags:>8.1f}")
    print(f"first answer correct: {ok}/{total} · {agent} {opts['--model'] or ''} · {result['seconds']}s · {out}")
    return 0


def cmd_compare(args: list[str]) -> int:
    if len(args) != 2:
        die("usage: devguard eval compare BEFORE.json AFTER.json", 64)
    for p in args:
        if not Path(p).is_file():
            die(f"{p}: no such file", 66)
    a, b = (json.loads(Path(p).read_text(encoding="utf-8")) for p in args)
    rows_a = {r[0]: r for r in summarize(a)}
    rows_b = {r[0]: r for r in summarize(b)}
    print(f"{a.get('label')} -> {b.get('label')}")
    print(f"{'case':24} {'correct':>12} {'flips':>10} {'tags/ans':>14}")
    for cid in dict.fromkeys([*rows_a, *rows_b]):
        ra, rb = rows_a.get(cid), rows_b.get(cid)
        if not ra or not rb:
            print(f"{cid[:24]:24} only in {'after' if rb else 'before'}")
            continue
        ok_a, ok_b = f"{ra[2]}/{ra[1]}", f"{rb[2]}/{rb[1]}"
        fl_a = f"{ra[4]}/{ra[3]}" if ra[3] else "-"
        fl_b = f"{rb[4]}/{rb[3]}" if rb[3] else "-"
        print(f"{cid[:24]:24} {ok_a:>5} -> {ok_b:<5} {fl_a:>5} -> {fl_b:<5} {ra[5]:>5.1f} -> {rb[5]:<5.1f}")
    return 0


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if argv else 64
    if argv[0] == "run":
        return cmd_run(argv[1:])
    if argv[0] == "compare":
        return cmd_compare(argv[1:])
    die(f"unknown command '{argv[0]}' (run, compare)", 64)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
