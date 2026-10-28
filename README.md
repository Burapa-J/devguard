# agent-kit

An evidence-first working mode for AI coding agents, plus a small, opinionated set of tools, installed once and shared across **Claude Code**, **VS Code (Copilot)** and **Antigravity**.

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
| `rtk` | Compresses shell output before the agent reads it | Homebrew `rtk` | `rtk init -g` (per-agent flags) | off |
| `context-mode` | Sandboxed execution + indexed search | npm `context-mode@1.0.169` (Node ≥ 22.5) | MCP only, no hooks | off |

`rtk` is off by default because it can hide failing lines. `verified-dev` works around that with `agent-verify`, but turn rtk on only after you confirm that evidence still comes through.

## Install

Quit Claude Code, VS Code and Antigravity first. They rewrite their own config files and can overwrite changes made while they run.

```sh
git clone https://github.com/Burapa-J/A69-012-agent-kit.git ~/agent-kit
cd ~/agent-kit
./install.sh --dry-run                     # see every change first
./install.sh --with-hooks                  # working mode + codegraph + projectmem
./install.sh --with=none                   # working mode only
./install.sh --with=codegraph,projectmem,rtk
./install.sh --targets=claude              # only some agents: claude, vscode, antigravity
./status.sh                                # what is installed and wired
```

Then set up each project, either automatically or by hand:
```sh
./install.sh --with-hooks --auto-project=~/Developer   # new repos under ~/Developer: set up on first Claude Code session
agent-kit-project init-all ~/Developer                 # existing repos, once
agent-kit-project init                                 # one repo, by hand
```
Each setup adds `.verify/` to `.gitignore` and runs `codegraph init` and `pjm init`. Automatic setup runs in the background, only under the folders you list, once per repository; a `.agent-kit-skip` file opts a repository out. It relies on a Claude Code hook, so for repos opened only in VS Code or Antigravity run `init` yourself.
Note: `pjm init` also installs projectmem's git hooks and adds a "projectmem bridge" section to the project's `CLAUDE.md` and `AGENTS.md` that tells agents to call projectmem at session start.

Every file agent-kit changes is backed up to `~/.agent-kit-backup/<timestamp>/`. Re-running is safe. Rules go between `<!-- agent-kit:begin -->` / `<!-- agent-kit:end -->` markers; anything else in those files is left alone. Skills are symlinks, so `git pull` updates them everywhere.

### Coming from tokless

Remove it first so tools aren't wired twice: `tokless uninstall`. Install warns while `tokless` is still on your PATH.

### Where things go

| Agent | Rules block | Skill link | MCP config |
|---|---|---|---|
| Claude Code | `~/.claude/CLAUDE.md` | `~/.claude/skills/verified-dev` | `~/.claude.json` |
| VS Code / Copilot | `~/.copilot/copilot-instructions.md` | reads `~/.claude/skills` (or `~/.copilot/skills` if Claude Code is not a target) | `~/Library/Application Support/Code/User/mcp.json` |
| Antigravity | `~/.gemini/GEMINI.md` | `~/.gemini/config/skills/verified-dev`, `~/.gemini/antigravity-cli/skills/verified-dev` | `~/.gemini/antigravity/mcp_config.json` |

## Uninstall

```sh
./uninstall.sh --dry-run
./uninstall.sh            # remove rules, skill, hook and all component wiring; keep tool CLIs
./uninstall.sh --purge    # also remove tool CLIs that agent-kit installed
```

`--purge` never removes a CLI you installed yourself. agent-kit records ownership in `~/.agent-kit/` and keeps that record after a plain uninstall, so a later `--purge` still works.

Left in place on purpose, because they are the tools' own data: `~/.codegraph/`, `~/.projectmem/` and per-project `.codegraph/` / `.projectmem/`. Remove per project with `codegraph uninit` and `pjm hooks uninstall`.

## Verify after installing

1. Run `./status.sh`. Every core line should say `ok`, and each enabled component should be `wired` for your agents.
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
- **Hooks** (agent-kit's own) are installed for Claude Code only. VS Code hooks are in preview, and Antigravity IDE hooks are not reliably documented yet.
- **rtk** has no documented unwire for Copilot. Uninstall warns you to remove its hook by hand.
- **codegraph unwire** is all-or-nothing upstream. Uninstall removes codegraph from every agent at once.

## Customize for your stack

The workflow (sections 1, 2 and 4-9 of the skill) is stack-neutral. Section 3's verification table is written for Swift/macOS; replace its rows with your stack's real surfaces. To add a component, copy `components/context-mode.sh`, implement the same functions, and add its name to `ALL_COMPONENTS` in `components/common.sh`.

## ภาษาไทย (สรุป)

คู่มือใช้งานฉบับเต็มภาษาไทย: [`docs/USAGE.th.md`](docs/USAGE.th.md)

agent-kit มี 2 ชั้น
- **วิธีทำงาน** (ติดตั้งเสมอ): rules และ skill ที่บังคับให้ agent เลือก playbook ตามประเภทงาน, กำหนด data shape ก่อนเขียนโค้ด, verify บนของจริง และห้ามบอกว่าเสร็จถ้าไม่มีหลักฐาน
- **Components** (เลือกได้): เครื่องมือของคนอื่นที่ติดตั้งจาก upstream โดยตรงแบบ pin version แล้ว wire เข้าแต่ละ agent ให้ ค่าเริ่มต้นคือ codegraph + projectmem ส่วน rtk และ context-mode ต้องเลือกเอง และไม่มี headroom

ติดตั้งด้วย `./install.sh --dry-run` ก่อน แล้วค่อย `./install.sh --with-hooks` ตรวจสถานะด้วย `./status.sh` และในแต่ละโปรเจกต์ให้รัน `agent-kit-project init` ถอนด้วย `./uninstall.sh` (เก็บ CLI ไว้) หรือ `./uninstall.sh --purge` (ลบ CLI ที่ agent-kit ติดตั้งให้ด้วย) ไฟล์ที่ถูกแก้จะถูก backup ไว้ที่ `~/.agent-kit-backup/` ถ้าเคยใช้ tokless ให้รัน `tokless uninstall` ก่อน

## Credits

The `verified-dev` workflow adapts ideas from [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan ([@poteto](https://github.com/poteto)), MIT licensed. Components install and wire third-party tools from their own projects: [codegraph](https://github.com/colbymchenry/codegraph), [projectmem](https://github.com/riponcm/projectmem), [rtk](https://github.com/rtk-ai/rtk), [context-mode](https://github.com/mksglu/context-mode). No third-party code is vendored. See `NOTICE`.
