#!/usr/bin/env python3
"""devguard real-time and batch iCloud Drive CRDT sync for projectmem.

Architecture:
- Each machine writes ONLY to its own per-device node files on iCloud Drive:
    <SYNC_DIR>/global/nodes/<device_id>.json
    <SYNC_DIR>/projects/<project_key>/nodes/<device_id>.jsonl
    <SYNC_DIR>/projects/<project_key>/docs/<device_id>-PROJECT_MAP.md
    <SYNC_DIR>/projects/<project_key>/docs/<device_id>-plan.md
- Because no two machines ever write to the same file on iCloud Drive, write-write
  collisions and iCloud ' 2.jsonl' conflict files are impossible by construction.
- Project identity (<project_key>) is derived from:
    1. Git root commit SHA (`root-<sha12>`) — invariant across folder renames and
       GitHub repository renames.
    2. Normalized `remote.origin.url` (`remote-<sha12>`) if the repo has 0 commits.
    3. Folder name (`dir-<sha12>`) only if the repo has 0 commits and no remote.
- When merging `nodes/*.jsonl` from multiple machines, sequential numeric issue IDs
  (`0001`, `0002`, ...) that collided while offline are automatically renumbered
  along with their linked `attempt`/`fix` events from that device.
"""
from __future__ import annotations

import hashlib
import json
import os
import platform
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

PLACEHOLDER_PHRASES = (
    "Not described yet.",
    "Short description of what the project does.",
    "Replace this placeholder",
    "Status: not created yet",
    "This file should be created by the first AI assistant",
)
DEFAULT_PLAN_SIGNATURES = (
    "_Loose thoughts, not yet committed to._",
    "_What we're working toward now. Use `- [ ]` / `- [x]` checklists._",
)


def default_sync_dir() -> Path:
    env = os.environ.get("DEVGUARD_SYNC_DIR")
    if env:
        return Path(env).expanduser().resolve()
    return Path.home() / "Library" / "Mobile Documents" / "com~apple~CloudDocs" / "devguard-sync"


def get_device_id() -> str:
    env = os.environ.get("DEVGUARD_DEVICE_ID")
    if env:
        return re.sub(r"[^A-Za-z0-9_.-]", "-", env)
    cache_file = Path.home() / ".agent-kit" / "device-id"
    if cache_file.is_file():
        try:
            val = cache_file.read_text(encoding="utf-8").strip()
            if val:
                return val
        except OSError:
            pass
    dev_id = ""
    if sys.platform == "darwin":
        try:
            out = subprocess.run(
                ["ioreg", "-rd1", "-c", "IOPlatformExpertDevice"],
                capture_output=True,
                text=True,
                timeout=2,
                stdin=subprocess.DEVNULL,
            ).stdout
            m = re.search(r'"IOPlatformUUID"\s*=\s*"([^"]+)"', out)
            if m:
                dev_id = m.group(1).lower()[:12]
        except Exception:
            pass
    host = re.sub(r"[^A-Za-z0-9-]", "", platform.node().split(".")[0]).lower() or "mac"
    if not dev_id:
        dev_id = hashlib.sha256(f"{host}-{Path.home()}".encode()).hexdigest()[:12]
    full_id = f"{host}-{dev_id}"
    try:
        cache_file.parent.mkdir(parents=True, exist_ok=True)
        cache_file.write_text(full_id + "\n", encoding="utf-8")
    except OSError:
        pass
    return full_id


def materialize_icloud_stubs(directory: Path) -> None:
    """If macOS Optimize Storage left .*.icloud stubs, trigger brctl download."""
    if not directory.is_dir():
        return
    stubs = list(directory.glob(".*.icloud"))
    if not stubs:
        return
    for stub in stubs:
        try:
            subprocess.run(
                ["brctl", "download", str(stub)],
                capture_output=True,
                timeout=5,
                stdin=subprocess.DEVNULL,
            )
        except Exception:
            pass


def atomic_write_if_changed(target: Path, content: str) -> bool:
    """Write `content` to `target` atomically only if its bytes actually changed."""
    try:
        if target.is_file() and target.read_text(encoding="utf-8") == content:
            return False
    except OSError:
        pass
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=str(target.parent), prefix=".tmp-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(content)
        os.replace(tmp_name, target)
        return True
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        return False


def replace_keeping_appends(target: Path, content: str, snapshot_len: int, known_ids: set[str]) -> bool:
    """Atomically replace `target`, then re-append lines other processes appended after `snapshot_len`.

    projectmem appends with open("a") and no lock (storage.append_event), so a plain replace would
    drop any event written between our read and os.replace. Holding the old inode open lets us read
    those late lines back; lines whose id is already in `known_ids` were merged and are skipped.
    """
    try:
        old = target.open("rb")
    except OSError:
        return atomic_write_if_changed(target, content)
    with old:
        if not atomic_write_if_changed(target, content):
            return False
        time.sleep(0.02)  # let a writer that opened the old file before the replace finish its write
        old.seek(snapshot_len)
        tail = old.read().decode("utf-8", errors="replace")
    written = set(content.splitlines())
    rescued = []
    for raw in tail.splitlines():
        line = raw.strip()
        if not line or line in written:
            continue
        try:
            eid = str(json.loads(line).get("id") or "")
        except (json.JSONDecodeError, AttributeError):
            continue
        if eid and eid in known_ids:
            continue
        rescued.append(line)
    if rescued:
        with target.open("a", encoding="utf-8") as fh:
            fh.write("\n".join(rescued) + "\n")
    return True


def normalize_remote_url(url: str) -> str:
    u = url.strip().lower()
    u = re.sub(r"^https?://", "", u)
    u = re.sub(r"^ssh://git@", "", u)
    u = re.sub(r"^git@([^:]+):", r"\1/", u)
    u = re.sub(r"\.git$", "", u)
    return u.strip("/")


def project_identity(repo_root: Path) -> dict[str, str]:
    """Compute stable cross-machine project key from root commit SHA or remote URL."""
    root_sha = ""
    remote_url = ""
    try:
        res = subprocess.run(
            ["git", "-C", str(repo_root), "rev-list", "--max-parents=0", "HEAD"],
            capture_output=True,
            text=True,
            timeout=3,
            stdin=subprocess.DEVNULL,
        )
        if res.returncode == 0 and res.stdout.strip():
            # Pick the earliest/first root commit deterministically
            lines = [ln.strip() for ln in res.stdout.splitlines() if ln.strip()]
            if lines:
                root_sha = lines[-1]
    except Exception:
        pass

    try:
        res = subprocess.run(
            ["git", "-C", str(repo_root), "config", "--get", "remote.origin.url"],
            capture_output=True,
            text=True,
            timeout=2,
            stdin=subprocess.DEVNULL,
        )
        if res.returncode == 0 and res.stdout.strip():
            remote_url = normalize_remote_url(res.stdout.strip())
    except Exception:
        pass

    if root_sha:
        key = f"root-{root_sha[:12]}"
    elif remote_url:
        h = hashlib.sha256(remote_url.encode()).hexdigest()[:12]
        key = f"remote-{h}"
    else:
        h = hashlib.sha256(repo_root.name.lower().encode()).hexdigest()[:12]
        key = f"dir-{h}"

    return {
        "project_key": key,
        "root_commit": root_sha,
        "remote_url": remote_url,
        "name": repo_root.name,
    }


def _parse_jsonl_events(path: Path, source_tag: str) -> list[tuple[str, dict[str, Any]]]:
    if not path.is_file():
        return []
    out: list[tuple[str, dict[str, Any]]] = []
    try:
        for raw in path.read_text(encoding="utf-8-sig").splitlines():
            line = raw.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                if isinstance(obj, dict) and "type" in obj and "summary" in obj:
                    out.append((source_tag, obj))
            except json.JSONDecodeError:
                continue
    except OSError:
        pass
    return out


def _issue_identity_key(ev: dict[str, Any]) -> str:
    gcommit = str(ev.get("git_commit") or "")
    summ = str(ev.get("summary") or "").strip()
    if ev.get("auto_captured") and gcommit:
        return f"auto:{gcommit}:{summ}"
    eid = str(ev.get("id") or "")
    return eid or f"{ev.get('timestamp')}:{summ}"


def merge_event_streams(
    streams: list[list[tuple[str, dict[str, Any]]]]
) -> tuple[list[dict[str, Any]], dict[str, str]]:
    """Merge multiple event streams as a commutative/idempotent CRDT join-semilattice.

    Returns (merged_events, local_issue_remap) where local_issue_remap maps any
    renumbered sequential issue_id in the 'local:*' stream to its canonical issue_id.
    """
    # Step 1: Within each stream, link every child event (attempt/fix/hypothesis)
    # to the unique identity key of its parent issue in that stream.
    tagged_events: list[tuple[str, dict[str, Any], str | None]] = []
    unique_issues: dict[str, dict[str, Any]] = {}
    local_orig_iid_by_ikey: dict[str, str] = {}

    for stream in streams:
        issue_key_by_iid: dict[str, str] = {}
        for src, ev in stream:
            iid = str(ev.get("issue_id") or "")
            if ev.get("type") == "issue" and iid.isdigit():
                ikey = _issue_identity_key(ev)
                issue_key_by_iid[iid] = ikey
                ts = str(ev.get("timestamp") or "")
                eid = str(ev.get("id") or "")
                if ikey not in unique_issues:
                    unique_issues[ikey] = {
                        "ts": ts,
                        "eid": eid,
                        "candidates": {iid},
                    }
                else:
                    info = unique_issues[ikey]
                    if (ts, eid) < (info["ts"], info["eid"]):
                        info["ts"] = ts
                        info["eid"] = eid
                    info["candidates"].add(iid)
                if src.startswith("local:"):
                    local_orig_iid_by_ikey[ikey] = iid

        for src, ev in stream:
            iid = str(ev.get("issue_id") or "")
            p_ikey = issue_key_by_iid.get(iid) if iid.isdigit() else None
            tagged_events.append((src, ev, p_ikey))

    # Step 2: Assign a single deterministic sequential issue_id to each unique issue
    # in chronological order of creation.
    sorted_ikeys = sorted(
        unique_issues.keys(),
        key=lambda k: (unique_issues[k]["ts"], unique_issues[k]["eid"], k),
    )
    claimed_iids: set[str] = set()
    max_num_id = 0
    for info in unique_issues.values():
        for c_iid in info["candidates"]:
            if c_iid.isdigit():
                max_num_id = max(max_num_id, int(c_iid))

    canonical_iid_by_ikey: dict[str, str] = {}
    for ikey in sorted_ikeys:
        cands = sorted(unique_issues[ikey]["candidates"], key=lambda x: int(x))
        chosen: str | None = None
        for c_iid in cands:
            if c_iid not in claimed_iids:
                chosen = c_iid
                break
        if chosen is None:
            max_num_id += 1
            chosen = f"{max_num_id:04d}"
        else:
            max_num_id = max(max_num_id, int(chosen))
        claimed_iids.add(chosen)
        canonical_iid_by_ikey[ikey] = chosen

    local_issue_remap: dict[str, str] = {}
    for ikey, orig_iid in local_orig_iid_by_ikey.items():
        canon_iid = canonical_iid_by_ikey.get(ikey)
        if canon_iid and canon_iid != orig_iid:
            local_issue_remap[orig_iid] = canon_iid

    # Apply canonical issue_id to all linked events
    remapped_events: list[dict[str, Any]] = []
    for _, ev, p_ikey in tagged_events:
        ev_copy = dict(ev)
        if p_ikey and p_ikey in canonical_iid_by_ikey:
            ev_copy["issue_id"] = canonical_iid_by_ikey[p_ikey]
        remapped_events.append(ev_copy)

    # Step 3: Deduplicate by evt_id and by backfill signature
    seen_ids: set[str] = set()
    seen_backfill_sigs: set[tuple[str, str, str, str]] = set()
    unique_events: list[dict[str, Any]] = []

    for ev in remapped_events:
        eid = str(ev.get("id") or "")
        if eid and eid in seen_ids:
            continue
        gcommit = str(ev.get("git_commit") or "")
        etype = str(ev.get("type") or "")
        iid = str(ev.get("issue_id") or "")
        summ = str(ev.get("summary") or "").strip()
        if gcommit and (iid.startswith("legacy_") or ev.get("auto_captured")):
            bf_sig = (etype, iid, gcommit, summ)
            if bf_sig in seen_backfill_sigs:
                continue
            seen_backfill_sigs.add(bf_sig)
        if eid:
            seen_ids.add(eid)
        unique_events.append(ev)

    # Step 4: Sort chronologically while keeping issue before fix when timestamps match
    type_order = {"issue": 0, "hypothesis": 1, "attempt": 2, "fix": 3, "decision": 4, "note": 5}
    unique_events.sort(
        key=lambda e: (
            str(e.get("timestamp") or ""),
            type_order.get(str(e.get("type") or ""), 9),
            str(e.get("id") or ""),
        )
    )
    return unique_events, local_issue_remap


def is_placeholder_map(text: str) -> bool:
    if not text or not text.strip():
        return True
    return any(p in text for p in PLACEHOLDER_PHRASES)


def is_placeholder_plan(text: str) -> bool:
    if not text or not text.strip():
        return True
    # Default plan has both placeholder lines and no bullet items
    if all(sig in text for sig in DEFAULT_PLAN_SIGNATURES):
        non_template = [
            ln.strip()
            for ln in text.splitlines()
            if ln.strip().startswith("- ")
        ]
        return len(non_template) == 0
    return False


def sync_doc_file(
    local_path: Path,
    docs_dir: Path,
    device_id: str,
    doc_name: str,
    is_placeholder_fn,
) -> bool:
    """Sync a structural markdown file (PROJECT_MAP.md or plan.md) without letting placeholders win."""
    docs_dir.mkdir(parents=True, exist_ok=True)
    materialize_icloud_stubs(docs_dir)

    local_text = local_path.read_text(encoding="utf-8") if local_path.is_file() else ""
    local_mtime = local_path.stat().st_mtime if local_path.is_file() else 0.0
    local_real = bool(local_text) and not is_placeholder_fn(local_text)

    best_text = local_text if local_real else ""
    best_mtime = local_mtime if local_real else 0.0

    for remote_file in sorted(docs_dir.glob(f"*-{doc_name}")):
        if not remote_file.is_file():
            continue
        try:
            r_text = remote_file.read_text(encoding="utf-8")
            r_mtime = remote_file.stat().st_mtime
        except OSError:
            continue
        if is_placeholder_fn(r_text):
            continue
        if not best_text or r_mtime > best_mtime + 1.0:
            best_text = r_text
            best_mtime = r_mtime

    changed = False
    if best_text and best_text != local_text:
        if atomic_write_if_changed(local_path, best_text):
            changed = True

    # Publish our device's copy only if it has real (non-placeholder) content
    final_local = local_path.read_text(encoding="utf-8") if local_path.is_file() else ""
    if final_local and not is_placeholder_fn(final_local):
        my_doc = docs_dir / f"{device_id}-{doc_name}"
        atomic_write_if_changed(my_doc, final_local)

    return changed


def sync_global_memory(sync_dir: Path | None = None, device_id: str | None = None) -> dict[str, int]:
    """Two-way CRDT union sync for ~/.projectmem/global/ via per-device node JSON files."""
    sdir = sync_dir or default_sync_dir()
    dev = device_id or get_device_id()
    nodes_dir = sdir / "global" / "nodes"
    nodes_dir.mkdir(parents=True, exist_ok=True)
    materialize_icloud_stubs(nodes_dir)

    try:
        from projectmem.global_memory import export_all, import_all, read_gotchas, read_patterns
    except ImportError:
        return {"imported_patterns": 0, "imported_gotchas": 0}

    imported_p = 0
    imported_g = 0
    for node_file in sorted(nodes_dir.glob("*.json")):
        if not node_file.is_file():
            continue
        try:
            data = json.loads(node_file.read_text(encoding="utf-8-sig"))
            if isinstance(data, dict):
                # Content-based deduplication in case two machines auto-promoted
                # the same pattern/gotcha with different random UUIDs (global_memory.py:372,393).
                known_p_texts = {
                    str(p.get("pattern") or "").strip().lower() for p in read_patterns()
                }
                known_g_keys = {
                    (
                        str(g.get("library") or "").strip().lower(),
                        str(g.get("gotcha") or "").strip().lower(),
                    )
                    for g in read_gotchas()
                }
                filtered = dict(data)
                filtered["patterns"] = [
                    p
                    for p in data.get("patterns", [])
                    if isinstance(p, dict)
                    and str(p.get("pattern") or "").strip().lower() not in known_p_texts
                ]
                filtered["gotchas"] = [
                    g
                    for g in data.get("gotchas", [])
                    if isinstance(g, dict)
                    and (
                        str(g.get("library") or "").strip().lower(),
                        str(g.get("gotcha") or "").strip().lower(),
                    )
                    not in known_g_keys
                ]
                res = import_all(filtered, merge=True)
                imported_p += res.get("patterns", 0)
                imported_g += res.get("gotchas", 0)
        except Exception:
            continue

    # Export local state to this device's node file only if patterns/gotchas/preferences changed
    current = export_all()
    my_node = nodes_dir / f"{dev}.json"
    comparable_new = {
        "patterns": current.get("patterns", []),
        "gotchas": current.get("gotchas", []),
        "preferences": current.get("preferences", ""),
    }
    need_write = True
    if my_node.is_file():
        try:
            old_data = json.loads(my_node.read_text(encoding="utf-8-sig"))
            comparable_old = {
                "patterns": old_data.get("patterns", []),
                "gotchas": old_data.get("gotchas", []),
                "preferences": old_data.get("preferences", ""),
            }
            if comparable_old == comparable_new:
                need_write = False
        except Exception:
            need_write = True

    if need_write and (comparable_new["patterns"] or comparable_new["gotchas"] or comparable_new["preferences"]):
        atomic_write_if_changed(my_node, json.dumps(current, indent=2, sort_keys=True) + "\n")

    return {"imported_patterns": imported_p, "imported_gotchas": imported_g}


def sync_project_memory(
    repo_root: Path,
    sync_dir: Path | None = None,
    device_id: str | None = None,
    regenerate: bool = True,
) -> dict[str, Any]:
    """Two-way CRDT union sync for one repository's .projectmem/."""
    repo_root = repo_root.resolve()
    mem_dir = repo_root / ".projectmem"
    if not mem_dir.is_dir():
        return {"synced": False, "reason": "no .projectmem"}

    sdir = sync_dir or default_sync_dir()
    dev = device_id or get_device_id()
    ident = project_identity(repo_root)
    proj_key = ident["project_key"]

    bucket = sdir / "projects" / proj_key
    nodes_dir = bucket / "nodes"
    docs_dir = bucket / "docs"
    nodes_dir.mkdir(parents=True, exist_ok=True)
    materialize_icloud_stubs(nodes_dir)

    streams: list[list[tuple[str, dict[str, Any]]]] = []
    local_events_file = mem_dir / "events.jsonl"
    # Size before parsing: bytes past this point are re-checked after the rewrite (replace_keeping_appends).
    local_snapshot_len = local_events_file.stat().st_size if local_events_file.is_file() else 0
    local_stream = _parse_jsonl_events(local_events_file, f"local:{dev}")
    streams.append(local_stream)

    for node_file in sorted(nodes_dir.glob("*.jsonl")):
        streams.append(_parse_jsonl_events(node_file, f"node:{node_file.stem}"))

    merged, local_issue_remap = merge_event_streams(streams)

    # Append-only CRDT safety invariant: never overwrite local or node files if any
    # non-backfill event ID from any input stream is missing from the merged result,
    # or if merged is empty while any input file on disk is non-empty.
    required_ids = {
        str(ev.get("id"))
        for s in streams
        for _, ev in s
        if ev.get("id")
        and not (
            ev.get("git_commit")
            and (str(ev.get("issue_id") or "").startswith("legacy_") or ev.get("auto_captured"))
        )
    }
    merged_ids = {str(ev.get("id")) for ev in merged if ev.get("id")}
    if not required_ids.issubset(merged_ids):
        return {"synced": False, "reason": "safety invariant: refusing to drop event IDs"}
    if not merged and (
        (local_events_file.is_file() and local_events_file.stat().st_size > 0)
        or any(nf.stat().st_size > 0 for nf in nodes_dir.glob("*.jsonl") if nf.is_file())
    ):
        return {"synced": False, "reason": "safety invariant: refusing to write empty merge over non-empty file"}

    merged_text = (
        "\n".join(json.dumps(ev, sort_keys=True) for ev in merged) + ("\n" if merged else "")
    )

    # Only rewrite local events.jsonl when a remote node contributed new events or
    # a local issue_id collision was remapped — avoids dirtying git working trees
    # on repos that track .projectmem/ when only formatting/order differs.
    local_ids = {str(ev.get("id")) for _, ev in local_stream if ev.get("id")}
    local_needs_update = (
        bool(local_issue_remap)
        or len(merged) != len(local_stream)
        or local_ids != merged_ids
    )
    events_changed = (
        replace_keeping_appends(local_events_file, merged_text, local_snapshot_len, merged_ids)
        if local_needs_update
        else False
    )
    if merged:
        my_node = nodes_dir / f"{dev}.jsonl"
        atomic_write_if_changed(my_node, merged_text)

    # If the local active issue (.projectmem/.current_issue, storage.py:704) was renumbered
    # due to an offline collision, update the marker so subsequent attempts/fixes attach properly.
    cur_marker = mem_dir / ".current_issue"
    if local_issue_remap and cur_marker.is_file():
        try:
            cur_val = cur_marker.read_text(encoding="utf-8").strip()
            if cur_val in local_issue_remap:
                atomic_write_if_changed(cur_marker, local_issue_remap[cur_val])
        except OSError:
            pass

    map_changed = sync_doc_file(
        mem_dir / "PROJECT_MAP.md", docs_dir, dev, "PROJECT_MAP.md", is_placeholder_map
    )
    plan_changed = sync_doc_file(
        mem_dir / "plan.md", docs_dir, dev, "plan.md", is_placeholder_plan
    )

    # Write human-readable meta.json only when identity fields change
    meta_file = bucket / "meta.json"
    meta_comparable = {
        "project_key": proj_key,
        "root_commit": ident["root_commit"],
        "remote_url": ident["remote_url"],
        "last_seen_name": ident["name"],
    }
    write_meta = True
    if meta_file.is_file():
        try:
            existing_meta = json.loads(meta_file.read_text(encoding="utf-8"))
            if all(existing_meta.get(k) == v for k, v in meta_comparable.items()):
                write_meta = False
        except Exception:
            write_meta = True
    if write_meta:
        meta_payload = {
            **meta_comparable,
            "last_device": dev,
            "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        atomic_write_if_changed(meta_file, json.dumps(meta_payload, indent=2, sort_keys=True) + "\n")

    if regenerate and (events_changed or map_changed):
        try:
            from projectmem.summary import regenerate_summary

            # Remove stale issue markdown files (summary.py:297 write_issue_files never deletes
            # old slugs/IDs) before regenerating all current issue files from merged events.
            issues_path = mem_dir / "issues"
            if issues_path.is_dir():
                for old_md in issues_path.glob("*.md"):
                    try:
                        old_md.unlink()
                    except OSError:
                        pass
            regenerate_summary(repo_root)
        except Exception:
            pass

    return {
        "synced": True,
        "project_key": proj_key,
        "name": ident["name"],
        "events_total": len(merged),
        "events_changed": events_changed,
        "map_changed": map_changed,
        "plan_changed": plan_changed,
    }


# ── Real-time hook for projectmem Python venv (installed via .pth) ──────────

_LAST_SYNC_TS: dict[str, float] = {}
_IN_HOOK = False


def _throttled_sync_project(root: Path | None, force: bool = False) -> None:
    global _IN_HOOK
    if _IN_HOOK or os.environ.get("DEVGUARD_NO_SYNC") == "1":
        return
    try:
        target_root = (root or Path.cwd()).resolve()
        if not (target_root / ".projectmem" / "config.toml").is_file():
            # Walk up to find initialized .projectmem
            for parent in [target_root, *target_root.parents]:
                if (parent / ".projectmem" / "config.toml").is_file():
                    target_root = parent
                    break
            else:
                return
        key = str(target_root)
        now = time.monotonic()
        if not force and (now - _LAST_SYNC_TS.get(key, 0.0)) < 2.0:
            return
        _LAST_SYNC_TS[key] = now
        _IN_HOOK = True
        try:
            sync_project_memory(target_root, regenerate=True)
        finally:
            _IN_HOOK = False
    except Exception:
        _IN_HOOK = False


def _throttled_sync_global(force: bool = False) -> None:
    global _IN_HOOK
    if _IN_HOOK or os.environ.get("DEVGUARD_NO_SYNC") == "1":
        return
    now = time.monotonic()
    if not force and (now - _LAST_SYNC_TS.get("__global__", 0.0)) < 5.0:
        return
    _LAST_SYNC_TS["__global__"] = now
    _IN_HOOK = True
    try:
        sync_global_memory()
    except Exception:
        pass
    finally:
        _IN_HOOK = False


def install_runtime_hooks() -> None:
    """Wrap projectmem.storage and projectmem.global_memory for real-time Read-Fresh & Write-Through."""
    if os.environ.get("DEVGUARD_NO_SYNC") == "1":
        return
    try:
        import projectmem.global_memory as gm
        import projectmem.storage as st
    except ImportError:
        return

    if getattr(st, "_devguard_hooked", False):
        return
    st._devguard_hooked = True  # type: ignore[attr-defined]

    orig_read_events = st.read_events
    orig_append_event = st.append_event
    orig_summary_path = st.summary_path
    orig_map_path = st.project_map_path
    orig_plan_path = st.plan_path
    orig_issues_dir = st.issues_dir

    def hooked_read_events(root: Path | None = None):
        _throttled_sync_project(root, force=False)
        return orig_read_events(root)

    def hooked_append_event(event, root: Path | None = None):
        _throttled_sync_project(root, force=False)
        res = orig_append_event(event, root)
        _throttled_sync_project(root, force=True)
        _throttled_sync_global(force=True)
        return res

    def hooked_summary_path(root: Path | None = None) -> Path:
        _throttled_sync_project(root, force=False)
        return orig_summary_path(root)

    def hooked_map_path(root: Path | None = None) -> Path:
        _throttled_sync_project(root, force=False)
        return orig_map_path(root)

    def hooked_plan_path(root: Path | None = None) -> Path:
        _throttled_sync_project(root, force=False)
        return orig_plan_path(root)

    def hooked_issues_dir(root: Path | None = None) -> Path:
        _throttled_sync_project(root, force=False)
        return orig_issues_dir(root)

    st.read_events = hooked_read_events
    st.append_event = hooked_append_event
    st.summary_path = hooked_summary_path
    st.project_map_path = hooked_map_path
    st.plan_path = hooked_plan_path
    st.issues_dir = hooked_issues_dir

    orig_read_gotchas = gm.read_gotchas
    orig_read_patterns = gm.read_patterns

    def hooked_read_gotchas():
        _throttled_sync_global(force=False)
        return orig_read_gotchas()

    def hooked_read_patterns():
        _throttled_sync_global(force=False)
        return orig_read_patterns()

    gm.read_gotchas = hooked_read_gotchas
    gm.read_patterns = hooked_read_patterns


def main(argv: list[str]) -> int:
    quiet = "--quiet" in argv or "-q" in argv
    args = [a for a in argv if a not in ("--quiet", "-q")]

    sdir = default_sync_dir()
    dev = get_device_id()

    if args and args[0] == "install-hook":
        # Install .pth file into projectmem-venv site-packages so every MCP/CLI run activates hooks
        import site

        sp_dirs = site.getsitepackages()
        if not sp_dirs:
            return 1
        sp = Path(sp_dirs[0])
        kit_bin = str(Path(__file__).resolve().parent)
        pth_content = (
            f"import sys; sys.path.insert(0, {kit_bin!r}); "
            "import pjm_sync; pjm_sync.install_runtime_hooks()\n"
        )
        atomic_write_if_changed(sp / "devguard_pjm_sync.pth", pth_content)
        return 0

    g_res = sync_global_memory(sdir, dev)

    repos: list[Path] = []
    if args:
        for a in args:
            p = Path(a).expanduser().resolve()
            if (p / ".projectmem").is_dir():
                repos.append(p)
    else:
        # Discover from ~/.projectmem/projects.json + ~/.agent-kit/auto-roots
        seen: set[str] = set()
        reg_file = Path.home() / ".projectmem" / "projects.json"
        if reg_file.is_file():
            try:
                data = json.loads(reg_file.read_text(encoding="utf-8"))
                items = data.get("projects", []) if isinstance(data, dict) else data
                for item in items:
                    p_str = item.get("path") if isinstance(item, dict) else str(item)
                    if p_str and p_str not in seen and (Path(p_str) / ".projectmem").is_dir():
                        seen.add(p_str)
                        repos.append(Path(p_str))
            except Exception:
                pass
        roots_file = Path.home() / ".agent-kit" / "auto-roots"
        roots = (
            [Path(r.strip()) for r in roots_file.read_text(encoding="utf-8").splitlines() if r.strip()]
            if roots_file.is_file()
            else ([Path.home() / "Developer"] if (Path.home() / "Developer").is_dir() else [])
        )
        for root in roots:
            if not root.is_dir():
                continue
            for pjm_dir in sorted(root.glob("*/.projectmem")) + sorted(root.glob("*/*/.projectmem")):
                repo = pjm_dir.parent.resolve()
                if str(repo) not in seen and (pjm_dir / "config.toml").is_file():
                    seen.add(str(repo))
                    repos.append(repo)

    synced_count = 0
    changed_count = 0
    total_events = 0
    for r in repos:
        res = sync_project_memory(r, sdir, dev, regenerate=True)
        if res.get("synced"):
            synced_count += 1
            total_events += int(res.get("events_total", 0))
            if res.get("events_changed") or res.get("map_changed") or res.get("plan_changed"):
                changed_count += 1

    if not quiet:
        print(
            f"devguard sync: device={dev} hub={sdir}\n"
            f"  global: +{g_res['imported_patterns']} patterns, +{g_res['imported_gotchas']} gotchas\n"
            f"  projects: {synced_count} synced ({changed_count} updated locally, {total_events} total events)"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
