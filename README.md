# potless (agent-kit)

An evidence-first working mode (`poteto` / `pstack` style) plus token-saving tools (`tokless` style), installed once and shared across **Claude Code**, **VS Code (Copilot)**, **Antigravity**, **OpenCode**, **Cursor**, **Codex CLI**, and **Gemini CLI**.

Two layers:
- **Working mode** (always installed): rules and a skill that control *how* the agent works. It picks a playbook, names the data shape, verifies on the real surface, and never calls something "done" without evidence.
- **Components** (opt-in, pinned versions): third-party tools installed from their upstream projects and wired into each agent. They replace a tokless-style bundle with only the parts you choose. **No prompt proxy (headroom) is included.**

## What's inside

| Path | Kind | Loaded |
|---|---|---|
| `rules/core.md` | Always-on instruction (6 lines) | Every prompt, via each agent's global rules file |
| `skills/verified-dev/SKILL.md` | On-demand instruction | When the agent matches it, or you type `/verified-dev` |
| `bin/verify.sh` → `agent-verify` | Tool | Agent runs it to capture full output + exit code into `.verify/<name>.log` |
| `bin/project.sh` → `agent-kit-project` | Tool | You run `agent-kit-project init` once per repo |
| `hooks/remind.sh` | Mechanism (Claude Code, opt-in) | After context compaction, reminds the agent to re-load the skill |
| `components/*.sh` | Installers | Install, wire, unwire and remove each tool |

## Components

| Component | What it does | Installed from | Wired as | Default |
|---|---|---|---|---|
| `codegraph` | Code graph search (`codegraph_explore`); supports Swift and ObjC | npm `@colbymchenry/codegraph@1.6.2` | Its own `codegraph install` (MCP + marked CLAUDE.md section + prompt hook); telemetry turned off | on |
| `projectmem` | Per-project memory: issues, attempts, fixes, decisions | PyPI `projectmem==0.3.4` in its own venv (`~/.local/share/agent-kit/projectmem-venv`) | One global MCP server for all projects | on |
| `rtk` | Compresses shell output before the agent reads it | Homebrew `rtk` | `rtk init -g` (per-agent flags) | on |
| `context-mode` | Sandboxed execution + indexed search | npm `context-mode@1.0.169` (Node ≥ 22.5) | MCP only, no hooks | off |

`rtk` compresses routine shell output while `verified-dev` captures full verification logs into `.verify/<name>.log` via `agent-verify` and reads them with the file-read tool, so failing lines are never lost.

## Install

One command on a new Mac (quit Claude Code, VS Code and Antigravity first):

```sh
brew install gh && gh auth login     # first time only; the repo is private
gh api -H 'Accept: application/vnd.github.raw' repos/Burapa-J/A69-012-agent-kit/contents/bootstrap.sh | bash
```

It installs missing prerequisites with Homebrew, clones the kit to `~/.local/share/agent-kit/src` (or reuses an existing clone), and runs `install.sh` with the recommended defaults:
- rules and skill for all three agents
- the compaction hook
- codegraph, projectmem and rtk
- **automatic setup of every git repository under `~/Developer`**

Then open a new terminal, restart your agents, and run `agent-kit status`.

Already cloned? Run `./install.sh`. Options (all optional): `--with=LIST`, `--auto-project=DIRS|none`, `--targets=LIST`, `--no-hooks`, `--dry-run`. See `./install.sh --help`. To pass them through bootstrap, use `... | bash -s -- --with=codegraph,projectmem,rtk,context-mode`.

### Everyday commands

```sh
potless                 # interactive menu (status, select tools, stats, update, uninstall)
potless status          # compact overview table of what is installed, wired and set up
potless stats           # unified token savings (rtk, projectmem) & codegraph index stats
potless select          # interactively pick agents and tools to enable/disable
potless update          # pull the latest kit, upgrade tools and re-apply settings
potless init [--all]    # set up this repo now, or every repo under your auto-setup folders
potless skip            # never set up this repo automatically
potless disable         # interactive uninstall / unwire (or: potless uninstall [--purge])
```
*(All commands also work under the `agent-kit` alias.)*

### Automatic project setup

Each repository under your auto-setup folders (default `~/Developer`, 1–2 levels deep) is set up once: `.verify/` goes into `.gitignore`, then `codegraph init` and `pjm init` run. It is triggered three ways, so every agent is covered:

| Trigger | Covers |
|---|---|
| Claude Code session start (hook) | Claude Code |
| `cd` into a repo in zsh | every agent's integrated terminal, and yours |
| launchd scan every 30 min and at login (macOS) | everything, including repos cloned from a GUI |

Setup runs in the background, ready repos are skipped instantly, and logs go to `~/.agent-kit/logs/`. Repositories outside the folders are never touched, and a `.agent-kit-skip` file opts one out (the kit's own repo has one).

Unlike tokless, `pjm init` writes into each project: it installs git hooks and adds a "projectmem bridge" section to the project's `CLAUDE.md` and `AGENTS.md`. That is why setup is limited to your own folders.

### Coming from tokless

Remove it first so tools aren't wired twice: `tokless uninstall`. Install warns while `tokless` is still on your PATH.

### Where things go

| Agent | Rules block | Skill link | MCP config |
|---|---|---|---|
| Claude Code | `~/.claude/CLAUDE.md` | `~/.claude/skills/verified-dev` | `~/.claude.json` |
| VS Code / Copilot | `~/.copilot/copilot-instructions.md` | reads `~/.claude/skills` (or `~/.copilot/skills` if Claude Code is not a target) | `~/Library/Application Support/Code/User/mcp.json` |
| Antigravity | `~/.gemini/GEMINI.md` | `~/.gemini/config/skills/verified-dev`, `~/.gemini/antigravity-cli/skills/verified-dev` | `~/.gemini/antigravity/mcp_config.json` (or `~/.gemini/config/mcp_config.json`) |
| OpenCode | `~/.config/opencode/AGENTS.md` | `~/.config/opencode/skills/verified-dev` | `~/.config/opencode/opencode.json` |
| Cursor | `~/.cursor/rules/agent-kit.mdc` | `~/.cursor/skills/verified-dev` | `~/.cursor/mcp.json` |
| Codex CLI | `~/.codex/AGENTS.md` | `~/.codex/skills/verified-dev` | `~/.codex/config.toml` |
| Gemini CLI | `~/.gemini/GEMINI.md` | `~/.gemini/skills/verified-dev` | `~/.gemini/settings.json` |

## Uninstall

```sh
agent-kit uninstall --dry-run
agent-kit uninstall            # remove rules, skill, hooks, zsh block, launchd agent and component wiring; keep tool CLIs
agent-kit uninstall --purge    # also remove tool CLIs that agent-kit installed
```

`--purge` never removes a CLI you installed yourself. agent-kit records ownership in `~/.agent-kit/` and keeps that record after a plain uninstall, so a later `--purge` still works.

Left in place on purpose, because they are the tools' own data: `~/.codegraph/`, `~/.projectmem/` and per-project `.codegraph/` / `.projectmem/`. Remove per project with `codegraph uninit` and `pjm hooks uninstall`.

## Verify after installing

1. Run `agent-kit status`. Every core line should say `ok`, and each enabled component should be `wired` for your agents.
2. Open a new session in each agent and ask: "What rules are you following for code tasks?" It should mention `verified-dev` and evidence.
3. Ask it to fix a bug that has a failing test. The reply should include the `agent-verify` log path, exit codes before and after, and the failing/passing lines.

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

คู่มือใช้งานฉบับเต็มภาษาไทย: [`docs/USAGE.th.md`](docs/USAGE.th.md)

agent-kit มี 2 ชั้น
- **วิธีทำงาน** (ติดตั้งเสมอ): rules และ skill ที่บังคับให้ agent เลือก playbook ตามประเภทงาน, กำหนด data shape ก่อนเขียนโค้ด, verify บนของจริง และห้ามบอกว่าเสร็จถ้าไม่มีหลักฐาน
- **Components** (เลือกได้): เครื่องมือของคนอื่นที่ติดตั้งจาก upstream โดยตรงแบบ pin version แล้ว wire เข้าแต่ละ agent ให้ ค่าเริ่มต้นคือ codegraph + projectmem + rtk ส่วน context-mode ต้องเลือกเอง และไม่มี headroom

ติดตั้งคำสั่งเดียวด้วย bootstrap (ดูส่วน Install) หรือรัน `./install.sh` ใน repo ที่ clone ไว้ ค่าเริ่มต้นตั้งค่าทุก repo ใน `~/Developer` ให้อัตโนมัติ ผ่าน Claude Code, การ `cd` ใน zsh และการสแกนของ launchd ทุก 30 นาที

ใช้งานผ่านคำสั่ง `agent-kit` เช่น `status`, `update`, `init --all`, `skip` และ `uninstall [--purge]` ไฟล์ที่ถูกแก้จะ backup ไว้ที่ `~/.agent-kit-backup/` ถ้าเคยใช้ tokless ให้รัน `tokless uninstall` ก่อน

## Credits

The `verified-dev` workflow adapts ideas from [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan ([@poteto](https://github.com/poteto)), MIT licensed. Components install and wire third-party tools from their own projects: [codegraph](https://github.com/colbymchenry/codegraph), [projectmem](https://github.com/riponcm/projectmem), [rtk](https://github.com/rtk-ai/rtk), [context-mode](https://github.com/mksglu/context-mode). No third-party code is vendored. See `NOTICE`.
