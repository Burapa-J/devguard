"""Locking and renumbering checks for bin/pjm_sync.py. Exit 0 = pass.

usage: sync_lock.py <kit_dir> <scratch_dir> <slow-writer|hook-lock|remap-rescue>
Needs DEVGUARD_SYNC_DIR and DEVGUARD_DEVICE_ID; HOME should be a throwaway directory (locks live there).
"""
import json
import multiprocessing as mp
import os
import subprocess
import sys
import time
from pathlib import Path

KIT, SCRATCH, CASE = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
sys.path.insert(0, str(KIT / "bin"))
import pjm_sync  # noqa: E402


def ev(eid, etype="note", ts="2026-10-30T00:00:00Z", **kw):
    return {"id": eid, "type": etype, "summary": eid, "timestamp": ts, **kw}


def jl(*events):
    return "".join(json.dumps(e, sort_keys=True) + "\n" for e in events)


def make_repo(name):
    repo = SCRATCH / name
    (repo / ".projectmem").mkdir(parents=True)
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t",
                    "commit", "-qm", "init", "--allow-empty"], check=True)
    (repo / ".projectmem" / "config.toml").write_text('[project]\nname = "x"\n')
    (repo / ".projectmem" / "events.jsonl").write_text("")
    return repo


def remote_node(repo):
    key = pjm_sync.project_identity(repo)["project_key"]
    node = Path(os.environ["DEVGUARD_SYNC_DIR"]) / "projects" / key / "nodes" / "other-mac.jsonl"
    node.parent.mkdir(parents=True, exist_ok=True)
    return node


def ids_in(path):
    return {json.loads(l)["id"]: json.loads(l) for l in path.read_text().splitlines() if l.strip()}


def slow_writer(repo, started):
    # A writer that holds the shared lock and takes 300 ms between open and write.
    with pjm_sync.events_lock(repo / ".projectmem"):
        with (repo / ".projectmem" / "events.jsonl").open("a") as h:
            started.set()
            time.sleep(0.3)
            h.write(jl(ev("evt_slow")))


def case_slow_writer():
    repo = make_repo("slow")
    remote_node(repo).write_text(jl(ev("evt_remote")))
    started = mp.Event()
    p = mp.Process(target=slow_writer, args=(repo, started))
    p.start()
    started.wait(5)
    pjm_sync.sync_project_memory(repo, regenerate=False)
    p.join()
    present = "evt_slow" in ids_in(repo / ".projectmem" / "events.jsonl")
    print(f"slow writer event kept: {present}")
    return present


def hold_lock(mem_dir, held, seconds):
    with pjm_sync.events_lock(mem_dir):
        held.set()
        time.sleep(seconds)


def case_hook_lock():
    repo = make_repo("hook")
    mem = repo / ".projectmem"
    fake = SCRATCH / "fakepkg" / "projectmem"
    fake.mkdir(parents=True)
    (fake / "__init__.py").write_text("")
    (fake / "global_memory.py").write_text("def read_gotchas(): return []\ndef read_patterns(): return []\n")
    (fake / "storage.py").write_text(
        "import json\nfrom pathlib import Path\n"
        f"MEM = Path({str(mem)!r})\n"
        "def events_path(root=None): return MEM / 'events.jsonl'\n"
        "def read_events(root=None): return events_path(root).read_text().splitlines()\n"
        "def append_event(event, root=None):\n"
        "    with events_path(root).open('a') as h: h.write(json.dumps(event) + '\\n')\n"
        "    return event\n"
        "def summary_path(root=None): return MEM / 'summary.md'\n"
        "def project_map_path(root=None): return MEM / 'PROJECT_MAP.md'\n"
        "def plan_path(root=None): return MEM / 'plan.md'\n"
        "def issues_dir(root=None): return MEM / 'issues'\n"
    )
    sys.path.insert(0, str(fake.parent))
    pjm_sync.install_runtime_hooks()
    import projectmem.storage as st

    held = mp.Event()
    p = mp.Process(target=hold_lock, args=(mem, held, 0.5))
    p.start()
    held.wait(5)
    # Skip the hook's own syncs before/after the append: they also wait on the lock and would
    # make this pass even if append_event itself ran unlocked.
    pjm_sync._IN_HOOK = True
    t0 = time.monotonic()
    st.append_event(ev("evt_hooked"), repo)
    waited = time.monotonic() - t0
    p.join()
    ok = waited >= 0.3 and "evt_hooked" in ids_in(mem / "events.jsonl")
    print(f"hooked append waited {waited:.2f}s for the lock")
    return ok


def case_remap_rescue():
    # Local issue 0001 collides with an older remote 0001, so the merge renumbers it to 0002.
    # Lines appended after the snapshot still use the old numbering and must follow it.
    repo = make_repo("remap")
    events = repo / ".projectmem" / "events.jsonl"
    local_issue = ev("evt_li", "issue", "2026-10-30T02:00:00Z", issue_id="0001")
    remote_node(repo).write_text(jl(ev("evt_ri", "issue", "2026-10-30T01:00:00Z", issue_id="0001")))
    events.write_text(jl(local_issue))
    snapshot = events.stat().st_size
    merged, remap = pjm_sync.merge_event_streams([
        pjm_sync._parse_jsonl_events(events, "local:a"),
        pjm_sync._parse_jsonl_events(remote_node(repo), "node:b"),
    ])
    with events.open("a") as h:  # written by a process that has not seen the renumbering
        h.write(jl(ev("evt_late_att", "attempt", "2026-10-30T03:00:00Z", issue_id="0001"),
                   ev("evt_new_issue", "issue", "2026-10-30T03:01:00Z", issue_id="0002"),
                   ev("evt_new_att", "attempt", "2026-10-30T03:02:00Z", issue_id="0002")))
    text = "".join(json.dumps(e, sort_keys=True) + "\n" for e in merged)
    pjm_sync.replace_keeping_appends(events, text, snapshot, {e["id"] for e in merged}, remap)
    pjm_sync.sync_project_memory(repo, regenerate=False)
    got = ids_in(events)
    want = {"evt_ri": "0001", "evt_li": "0002", "evt_late_att": "0002",
            "evt_new_issue": "0003", "evt_new_att": "0003"}
    actual = {k: got.get(k, {}).get("issue_id") for k in want}
    print(f"remap={remap} issue_ids={actual}")
    return actual == want


if __name__ == "__main__":
    ok = {"slow-writer": case_slow_writer, "hook-lock": case_hook_lock,
          "remap-rescue": case_remap_rescue}[CASE]()
    sys.exit(0 if ok else 1)
