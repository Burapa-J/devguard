# devguard

[![CI](https://github.com/Burapa-J/devguard/actions/workflows/test.yml/badge.svg)](https://github.com/Burapa-J/devguard/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

An evidence-first working mode (`poteto` / `pstack` style) plus token-saving tools (`tokless` style), installed once and shared across **Claude Code**, **VS Code (Copilot)**, **Antigravity**, **OpenCode**, **Cursor**, **Codex CLI**, and **Gemini CLI**.

Two layers:
- **Working mode** (always installed): rules and a skill that control *how* the agent works. It picks a playbook, names the data shape, verifies on the real surface, and never calls something "done" without evidence.
- **Components** (opt-in, pinned versions): third-party tools installed from their upstream projects and wired into each agent. They replace a tokless-style bundle with only the parts you choose. **No prompt proxy (headroom) is included.**

## What's inside

| Path | Kind | Loaded |
|---|---|---|
| `rules/core.md` | Always-on instruction (9 lines) | Every prompt, via each agent's global rules file |
| `skills/verified-dev/SKILL.md` | On-demand instruction | When the agent matches it, or you type `/verified-dev` |
| `bin/devguard` → `devguard` | CLI & interactive menu | Manage setup, status, doctor, stats, updates, and project init |
| `bin/doctor.sh` → `devguard doctor` | Health & repair tool | Audits 8 failure modes (legacy tokless, symlinks, conflicting plugins, MCP drift, RTK plugin, rules sync, version drift, memory sync) and repairs them with `--fix` |
| `bin/stats.sh` → `devguard stats` | Telemetry & quality summary | Shows RTK shell savings, ProjectMem fixes/tokens, CodeGraph index counts, and `.verify/*.log` verification pass rates |
| `bin/pjm_sync.py` → `devguard sync` | Multi-Mac memory sync | Real-time & batch CRDT sync of `projectmem` across machines over iCloud Drive |
| `bin/verify.sh` → `agent-verify` | Verification harness | Captures full output + exit code into `.verify/<name>.log` and reports error line numbers (`errors_at=L...`) |
| `bin/gate.sh` → `devguard check` / `devguard gate` | Done gate | Runs a repo's `.devguard/checks` and installs pre-commit / pre-push hooks that block on failure |
| `bin/project.sh` → `devguard-project` | Per-repo setup tool | Runs `codegraph init`, `pjm init`, and `.gitignore` setup per repository |
| `hooks/remind.sh` | Mechanism (Claude Code, opt-in) | After context compaction, reminds the agent to re-load the skill |
| `components/*.sh` | Installers | Install, upgrade, wire, unwire and remove each tool |

## Components

| Component | What it does | Installed from | Wired as | Default |
|---|---|---|---|---|
| `codegraph` | Code graph search (`codegraph_explore`); supports Swift and ObjC | npm `@colbymchenry/codegraph@1.6.2` | Its own `codegraph install` (MCP + marked CLAUDE.md section + prompt hook); telemetry turned off | on |
| `projectmem` | Per-project & global memory (issues, attempts, fixes, decisions) with real-time iCloud Drive CRDT sync | PyPI `projectmem==0.3.4` in its own venv (`~/.local/share/agent-kit/projectmem-venv`) | One global MCP server for all projects + `.pth` real-time sync hook | on |
| `rtk` | Compresses shell output before the agent reads it | Homebrew `rtk` | `rtk init -g` (per-agent flags) | on |
| `context-mode` | Sandboxed execution + indexed search | npm `context-mode@1.0.169` (Node ≥ 22.5) | MCP only, no hooks | off |

### Companion CLI Tools (installed by `bootstrap.sh` / `devguard update`)

| Tool | What it does | Installed from |
|---|---|---|
| `ast-grep` | Tree-sitter structural search & refactoring (`ast-grep run -p '<pattern>' -l swift`) | Homebrew `ast-grep` |
| `xcbeautify` | Condenses `xcodebuild` build/test logs into clean summaries (also used by `rtk` for Xcode output) | Homebrew `xcbeautify` |
| `shellcheck` | Static analysis for shell scripts; this kit runs it in its own commit gate | Homebrew `shellcheck` |

`rtk` compresses routine shell output while `verified-dev` captures full verification logs into `.verify/<name>.log` via `agent-verify` and reads them with the file-read tool, so failing lines are never lost.

## Install

One command on a new Mac (quit Claude Code, VS Code and Antigravity first):

```sh
curl -fsSL https://raw.githubusercontent.com/Burapa-J/devguard/main/bootstrap.sh | bash
```
*(If the repository is still private on your account, run `gh api -H 'Accept: application/vnd.github.raw' repos/Burapa-J/devguard/contents/bootstrap.sh | bash` instead.)*

It installs missing prerequisites with Homebrew, clones the kit to `~/.local/share/agent-kit/src` (or reuses an existing clone), and runs `install.sh` with the recommended defaults:
- rules and skill for all three agents
- the compaction hook
- codegraph, projectmem and rtk
- **automatic setup of every git repository under `~/Developer`**

Then open a new terminal, restart your agents, and run `devguard status`.

Already cloned? Run `./install.sh`. Options (all optional): `--with=LIST`, `--auto-project=DIRS|none`, `--targets=LIST`, `--no-hooks`, `--dry-run`. See `./install.sh --help`. To pass them through bootstrap, use `... | bash -s -- --with=codegraph,projectmem,rtk,context-mode`.

### Everyday commands

```sh
devguard                 # interactive menu (status, select tools, doctor, stats, update, uninstall)
devguard status          # compact overview table of what is installed, wired and set up
devguard doctor [--fix]  # audit 8 common failure modes and optionally repair them automatically
devguard stats           # unified token savings, codegraph index & verification pass-rate stats
devguard sync [--quiet]  # sync projectmem across machines over iCloud Drive (CRDT merge)
devguard check           # run this repo's .devguard/checks (the done gate)
devguard gate init       # write a checks template and install the git hooks
devguard select          # interactively pick agents and tools to enable/disable
devguard update          # pull the latest kit, upgrade tools and re-apply settings
devguard init [--all]    # set up this repo now, or every repo under your auto-setup folders
devguard skip            # never set up this repo automatically
devguard disable         # interactive uninstall / unwire (or: devguard uninstall [--purge])
```

### Done gate (`.devguard/checks`)

Rules and skills ask an agent to verify; the gate checks for it, whatever model wrote the code. Each repo lists its real checks in a committed `.devguard/checks`, one per line:

```
commit build: swift build        # every commit: keep it fast
push   test:  swift test         # before push: full suites
```

`devguard gate init` writes a commented template and installs `pre-commit` / `pre-push` hooks; `devguard check` runs everything by hand, and the core rule tells agents to run it before calling a task done. Each check runs through `agent-verify`, so a failure prints one line and leaves the full log in `.verify/gate-<name>.log`.

Safety: the hooks are only written where no hook exists or ours does (a foreign hook is left alone and you get the line to add), they follow linked worktrees and `core.hooksPath`, they let the commit through with a warning if the kit has moved, and a commit that edits `.devguard/checks` is flagged for review. Known limits: checks run on the working tree, not only the staged part, and `git commit --no-verify` still skips them.

### Automatic project setup

Each repository under your auto-setup folders (default `~/Developer`, 1–2 levels deep) is set up once: `.verify/` goes into `.gitignore`, then `codegraph init` and `pjm init` run. It is triggered three ways, so every agent is covered:

| Trigger | Covers |
|---|---|
| Claude Code session start (hook) | Claude Code |
| `cd` into a repo in zsh | every agent's integrated terminal, and yours |
| launchd scan every 30 min and at login (macOS) | everything, including repos cloned from a GUI |

Setup runs in the background, ready repos are skipped instantly, and logs go to `~/.agent-kit/logs/`. Repositories outside the folders are never touched, and a `.agent-kit-skip` file opts one out (the kit's own repo has one).

Unlike tokless, `pjm init` writes into each project: it installs git hooks, verifies `config.toml` and `~/.projectmem/projects.json` registration, and adds a "projectmem bridge" section to the project's `CLAUDE.md` and `AGENTS.md`. That is why setup is limited to your own folders.

### Cross-machine memory sync (iCloud Drive)

When iCloud Drive is signed in, `projectmem` automatically syncs project and global memories across all your Macs via `~/Library/Mobile Documents/com~apple~CloudDocs/devguard-sync/` using an append-only CRDT merge (`bin/pjm_sync.py`):
- **Conflict-free per-device files:** Each Mac writes only to its own `nodes/<device_id>.jsonl`, `docs/<device_id>-PROJECT_MAP.md`, `docs/<device_id>-plan.md`, and `global/nodes/<device_id>.json`, avoiding iCloud `events 2.jsonl` conflict copies.
- **Git root commit matching (`root-<sha12>`):** Repositories are matched across Macs by their initial Git commit SHA even if folder names differ.
- **Offline `issue_id` collision resolution:** Concurrent offline issues with the same number are deterministically renumbered with `parent_issue_key` linkage and `.projectmem/.current_issue` marker updates.
- **Zero-touch real-time sync:** A `.pth` runtime hook inside `projectmem-venv` syncs automatically on every MCP read/write, complemented by `cd`, `launchd`, and `devguard sync`.

### Coming from tokless / caveman / ponytail

Remove legacy tools first so hooks and plugins aren't wired twice: `tokless uninstall`, or simply run `devguard doctor --fix` after installing `devguard` to automatically clean up leftover `tokless` blocks, broken symlinks, and conflicting `caveman` / `ponytail` / `cavecrew` plugins.

### Where things go

| Agent | Rules block | Skill link | MCP config |
|---|---|---|---|
| Claude Code | `~/.claude/CLAUDE.md` | `~/.claude/skills/verified-dev` | `~/.claude.json` |
| VS Code / Copilot | `~/.copilot/copilot-instructions.md` | reads `~/.claude/skills` (or `~/.copilot/skills` if Claude Code is not a target) | `~/Library/Application Support/Code/User/mcp.json` |
| Antigravity | `~/.gemini/GEMINI.md` | `~/.gemini/config/skills/verified-dev`, `~/.gemini/antigravity-cli/skills/verified-dev` | `~/.gemini/config/mcp_config.json` |
| OpenCode | `~/.config/opencode/AGENTS.md` | `~/.config/opencode/skills/verified-dev` | `~/.config/opencode/opencode.jsonc` |
| Cursor | `~/.cursor/rules/devguard.mdc` | `~/.cursor/skills/verified-dev` | `~/.cursor/mcp.json` |
| Codex CLI | `~/.codex/AGENTS.md` | `~/.codex/skills/verified-dev` | `~/.codex/config.toml` |
| Gemini CLI | `~/.gemini/GEMINI.md` | `~/.gemini/skills/verified-dev` | `~/.gemini/settings.json` |

## Uninstall

```sh
devguard uninstall --dry-run
devguard uninstall            # remove rules, skill, hooks, zsh block, launchd agent and component wiring; keep tool CLIs
devguard uninstall --purge    # also remove tool CLIs that devguard installed
```

`--purge` never removes a CLI you installed yourself. devguard records ownership in `~/.agent-kit/` and keeps that record after a plain uninstall, so a later `--purge` still works.

Left in place on purpose, because they are the tools' own data: `~/.codegraph/`, `~/.projectmem/` and per-project `.codegraph/` / `.projectmem/`. Remove per project with `codegraph uninit` and `pjm hooks uninstall`.

## Verify after installing

1. Run `devguard status` and `devguard doctor`. Every core line should say `ok`, each enabled component should be `wired` for your agents, and `devguard doctor` should report `0 issues` (if not, run `devguard doctor --fix`).
2. Open a new session in each agent and ask: "What rules are you following for code tasks?" It should stay read-only, mention `verified-dev`, and cite runtime evidence requirements.
3. Ask it to fix a bug that has a failing test. The reply should include a compact summary and a one-line verification receipt (`agent-verify` log path, exit code, and key verdict), pasting raw log lines only for failures.

If step 3 comes back without evidence, an always-on rule from another setup is probably winning. See section 9 of the skill.

## Testing the kit itself

```sh
bash tests/test-kit.sh          # core: install / reinstall / uninstall
bash tests/test-components.sh   # components, with stub npm/python3/codegraph (no downloads)
```
Both run against a throwaway `HOME` and check that user content survives and that uninstall restores every file byte-for-byte. Needs `jq` and `git`.

## Known limits

- **VS Code** reads `~/.copilot/copilot-instructions.md` for the Copilot harness. Confirm your VS Code version picks it up by asking the agent what rules it has.
- **Agent hooks** (agent-kit's own) are installed for Claude Code only, because VS Code hooks are in preview and Antigravity IDE hooks are not reliably documented yet. Automatic project setup still covers those agents through zsh and launchd.
- **launchd** is macOS only. On Linux the zsh hook and the Claude Code hook still work.
- **rtk** has no documented unwire for Copilot. Uninstall warns you to remove its hook by hand.
- **codegraph unwire** is all-or-nothing upstream. Uninstall removes codegraph from every agent at once.

## Customize for your stack

The workflow (sections 1, 2 and 4-9 of the skill) is stack-neutral. Section 3's verification table is written for Swift/macOS; replace its rows with your stack's real surfaces. To add a component, copy `components/context-mode.sh`, implement the same functions, and add its name to `ALL_COMPONENTS` in `components/common.sh`.

## ภาษาไทย (สรุป)

คู่มือใช้งานฉบับเต็มภาษาไทย: [`docs/USAGE.th.md`](docs/USAGE.th.md) · รายการตรวจสอบอัปเดตจากต้นทาง (Upstream Radar): [`docs/UPSTREAM-RADAR.md`](docs/UPSTREAM-RADAR.md)

`devguard` มี 2 ชั้น
- **วิธีทำงาน** (ติดตั้งเสมอ): rules และ skill ที่บังคับให้ agent เลือก playbook ตามประเภทงาน, กำหนด data shape ก่อนเขียนโค้ด, verify บนของจริง และห้ามบอกว่าเสร็จถ้าไม่มีหลักฐาน
- **Components** (เลือกได้): เครื่องมือของคนอื่นที่ติดตั้งจาก upstream โดยตรงแบบ pin version แล้ว wire เข้าแต่ละ agent ให้ ค่าเริ่มต้นคือ codegraph + projectmem + rtk ส่วน context-mode ต้องเลือกเอง และไม่มี headroom

ติดตั้งคำสั่งเดียวด้วย bootstrap (ดูส่วน Install) หรือรัน `./install.sh` ใน repo ที่ clone ไว้ ค่าเริ่มต้นตั้งค่าทุก repo ใน `~/Developer` ให้อัตโนมัติ ผ่าน Claude Code, การ `cd` ใน zsh และการสแกนของ launchd ทุก 30 นาที

ใช้งานผ่านคำสั่ง `devguard` เช่น `status`, `doctor [--fix]`, `stats`, `sync [--quiet]`, `select`, `update`, `init [--all]`, `skip` และ `uninstall [--purge]` ความจำของ `projectmem` จะซิงค์ข้ามเครื่องผ่าน iCloud Drive แบบ CRDT อัตโนมัติ (จับคู่โปรเจกต์ด้วย Git root commit SHA แม้ชื่อโฟลเดอร์ต่างกัน) และไฟล์ที่ถูกแก้จะ backup ไว้ที่ `~/.agent-kit-backup/` (เก็บล่าสุดสูงสุด 10 ชุด) ถ้าเคยใช้ tokless หรือปลั๊กอิน caveman/ponytail ให้รัน `devguard doctor --fix` เพื่อเก็บกวาดคราบเก่าอัตโนมัติ

## Credits

The `verified-dev` workflow adapts ideas from [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan ([@poteto](https://github.com/poteto)), MIT licensed. Components install and wire third-party tools from their own projects: [codegraph](https://github.com/colbymchenry/codegraph), [projectmem](https://github.com/riponcm/projectmem), [rtk](https://github.com/rtk-ai/rtk), [context-mode](https://github.com/mksglu/context-mode). No third-party code is vendored. See `NOTICE`.
