"""Concurrency check for bin/pjm_sync.py: appends made while a sync rewrites events.jsonl must survive.

usage: sync_race.py <kit_dir> <repo_with_.projectmem>; needs DEVGUARD_SYNC_DIR and DEVGUARD_DEVICE_ID.
Prints "lost=<n>" and exits 1 if any appended event is missing.
"""
import json
import multiprocessing as mp
import os
import sys
import time
from pathlib import Path

KIT, REPO = Path(sys.argv[1]), Path(sys.argv[2])
EVENTS = REPO / ".projectmem" / "events.jsonl"
N = 2000


def line(i: int, prefix: str) -> str:
    return json.dumps({"id": f"evt_{prefix}{i:05d}", "type": "note", "summary": prefix,
                       "timestamp": "2026-10-30T00:00:00Z"}) + "\n"


def syncer(stop, runs) -> None:
    sys.path.insert(0, str(KIT / "bin"))
    import pjm_sync

    key = pjm_sync.project_identity(REPO)["project_key"]
    node = Path(os.environ["DEVGUARD_SYNC_DIR"]) / "projects" / key / "nodes" / "other-mac.jsonl"
    node.parent.mkdir(parents=True, exist_ok=True)
    n = 0
    while not stop.is_set():
        # A remote event on every pass forces sync to rewrite the local events.jsonl.
        with node.open("a") as h:
            h.write(line(n, "remote"))
        pjm_sync.sync_project_memory(REPO, regenerate=False)
        n += 1
    runs.value = n


if __name__ == "__main__":
    stop, runs = mp.Event(), mp.Value("i", 0)
    proc = mp.Process(target=syncer, args=(stop, runs))
    proc.start()
    time.sleep(0.3)
    for i in range(N):
        # Same write pattern as projectmem storage.append_event.
        with EVENTS.open("a") as h:
            h.write(line(i, "local"))
    time.sleep(0.5)
    stop.set()
    proc.join()
    ids = [json.loads(l)["id"] for l in EVENTS.read_text().splitlines() if l.strip()]
    present = {i for i in ids if i.startswith("evt_local")}
    dupes = len(ids) - len(set(ids))
    print(f"sync_runs={runs.value} lost={N - len(present)} duplicates={dupes}")
    sys.exit(0 if len(present) == N and dupes == 0 and runs.value > 0 else 1)
