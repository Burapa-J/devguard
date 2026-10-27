# agent-kit

An evidence-first working mode for AI coding agents, installed once and shared across **Claude Code**, **VS Code (Copilot)** and **Antigravity**.

It does not save tokens. It controls *how* the agent works: pick a playbook, name the data shape, verify on the real surface, and never call something "done" without evidence.

## What's inside

| Path | Kind | Loaded |
|---|---|---|
| `rules/core.md` | Always-on instruction (6 lines) | Every prompt, via each agent's global rules file |
| `skills/verified-dev/SKILL.md` | On-demand instruction | When the agent matches it, or you type `/verified-dev` |
| `bin/verify.sh` → `agent-verify` | Tool | Agent runs it to capture full output + exit code into `.verify/<name>.log` |
| `hooks/remind.sh` | Mechanism (Claude Code, opt-in) | After context compaction, reminds the agent to re-load the skill |

## Install

```sh
git clone <this repo> ~/agent-kit
cd ~/agent-kit
./install.sh --dry-run          # see what would change
./install.sh                    # rules + skill + agent-verify
./install.sh --with-hooks       # also add the Claude Code hook (needs jq)
./install.sh --targets=claude   # only some agents: claude, vscode, antigravity
```

Every file it changes is backed up to `~/.agent-kit-backup/<timestamp>/`. Re-running is safe. Rules go between `<!-- agent-kit:begin -->` / `<!-- agent-kit:end -->` markers; anything else in those files is left alone. Skills are symlinks, so `git pull` updates them everywhere.

Add `.verify/` to each project's `.gitignore`.

### Where things go

| Agent | Rules block | Skill link |
|---|---|---|
| Claude Code | `~/.claude/CLAUDE.md` | `~/.claude/skills/verified-dev` |
| VS Code / Copilot | `~/.copilot/copilot-instructions.md` | reads `~/.claude/skills` (or `~/.copilot/skills` if Claude Code is not a target) |
| Antigravity | `~/.gemini/GEMINI.md` | `~/.gemini/config/skills/verified-dev`, `~/.gemini/antigravity-cli/skills/verified-dev` |

## Uninstall

```sh
./uninstall.sh --dry-run
./uninstall.sh
```

Removes only the marked blocks, symlinks that point into this kit, and the hook entry carrying this kit's path.

## Verify after installing

1. Open a new session in each agent and ask: "What rules are you following for code tasks?" It should mention `verified-dev` and evidence.
2. Ask it to fix a bug that has a failing test. The reply should include the `agent-verify` log path, exit codes before and after, and the failing/passing lines.

If step 2 comes back without evidence, an always-on rule from another setup is probably winning. See section 9 of the skill.

## Testing the kit itself

```sh
bash tests/test-kit.sh
```
Installs, re-installs and uninstalls against a throwaway `HOME`, and checks that user content survives and uninstall restores every file byte-for-byte. Needs `jq`.

## Known limits

- **VS Code** reads `~/.copilot/copilot-instructions.md` for the Copilot harness; confirm your VS Code version picks it up (ask the agent what rules it has).
- **Hooks** are installed for Claude Code only. VS Code hooks are in preview and Antigravity IDE hooks are not reliably documented yet; both still get the rules and the skill.
- **Using with token-saving setups** (e.g. tokless): compatible. Section 9 of the skill handles brevity rules and output compressors. Prefer installing tools such as codegraph or projectmem from their upstream projects.

## Customize for your stack

The workflow (sections 1, 2, 4-9 of the skill) is stack-neutral. Section 3's verification table is written for Swift/macOS; replace its rows with your stack's real surfaces.

## ภาษาไทย (สรุป)

ชุดนี้ควบคุม *วิธีทำงาน* ของ AI agent ไม่ได้ช่วยลด token: เลือก playbook ตามประเภทงาน, กำหนด data shape ก่อนเขียนโค้ด, verify บนของจริง และห้ามบอกว่าเสร็จถ้าไม่มีหลักฐาน ติดตั้งด้วย `./install.sh` (ลอง `--dry-run` ก่อน) และถอนด้วย `./uninstall.sh` ไฟล์ที่ถูกแก้จะถูก backup ไว้ที่ `~/.agent-kit-backup/`

## Credits

The `verified-dev` workflow adapts ideas from [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan ([@poteto](https://github.com/poteto)), MIT licensed. See `NOTICE`.
