#!/usr/bin/env bash
# Install agent-kit rules, skill, agent-verify, optional hook, and selected tool components.
# Safe to re-run: every step is idempotent, and changed files are backed up first.
set -eu

KIT_DIR=$(cd "$(dirname "$0")" && pwd -P)
TARGETS="claude,vscode,antigravity"
WITH_HOOKS=0
DRY_RUN=0
WITH=""

usage() {
  cat <<EOF
Usage: ./install.sh [--dry-run] [--with-hooks] [--with=LIST] [--targets=LIST]

  --dry-run      Show what would change; change nothing.
  --with-hooks   Add a Claude Code SessionStart(compact) hook that reminds the agent
                 to re-load the skill after context compaction. Needs jq.
  --with=LIST    Tool components to install and wire, comma-separated, or "none".
                 Available: codegraph, projectmem, rtk, context-mode.
                 Default: codegraph,projectmem
  --targets=...  Comma-separated subset of: claude, vscode, antigravity (default: all).

Quit Claude Code, VS Code and Antigravity before installing: they rewrite their own
config files and can overwrite changes made while they run.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --with-hooks) WITH_HOOKS=1 ;;
    --with=*) WITH=${arg#--with=} ;;
    --targets=*) TARGETS=${arg#--targets=} ;;
    -h | --help) usage; exit 0 ;;
    *) echo "unknown option: $arg" >&2; usage >&2; exit 64 ;;
  esac
done

has_target() { case ",$TARGETS," in *",$1,"*) return 0 ;; esac; return 1; }

BACKUP_DIR=""
[ "$DRY_RUN" = 1 ] || BACKUP_DIR="$HOME/.agent-kit-backup/$(date +%Y%m%d-%H%M%S)"

# shellcheck source=lib.sh
. "$KIT_DIR/lib.sh"
# shellcheck source=components/common.sh
. "$KIT_DIR/components/common.sh"
load_components

[ -n "$WITH" ] || WITH=$DEFAULT_COMPONENTS
[ "$WITH" = none ] && WITH=""
for c in $(printf '%s' "$WITH" | tr ',' ' '); do
  valid_component "$c" || { echo "unknown component: $c (available: $ALL_COMPONENTS)" >&2; exit 64; }
done

RULES="$KIT_DIR/rules/core.md"
SKILL_SRC="$KIT_DIR/skills/$SKILL_NAME"

[ "$DRY_RUN" = 1 ] && say "Dry run: nothing will be changed."
[ "$DRY_RUN" = 1 ] || chmod +x "$KIT_DIR/bin/verify.sh" "$KIT_DIR/bin/project.sh" "$KIT_DIR/hooks/remind.sh"

if command -v tokless >/dev/null 2>&1; then
  warn "tokless is installed. It wires some of the same tools; run 'tokless uninstall' first to avoid duplicates."
fi

say "agent-verify, agent-kit-project"
link "$VERIFY_LINK" "$KIT_DIR/bin/verify.sh"
link "$PROJECT_LINK" "$KIT_DIR/bin/project.sh"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) warn "$HOME/.local/bin is not on PATH. Add to your shell profile: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

if has_target claude; then
  say "Claude Code"
  set_block "$CLAUDE_RULES" "$RULES"
  link "$CLAUDE_SKILLS/$SKILL_NAME" "$SKILL_SRC"
  if [ "$WITH_HOOKS" = 1 ]; then
    edit_settings "$JQ_ADD_HOOK"
  fi
fi

if has_target vscode; then
  say "VS Code / Copilot"
  set_block "$VSCODE_RULES" "$RULES"
  # VS Code also reads ~/.claude/skills; link here only when Claude Code is not a target,
  # otherwise the skill would be listed twice.
  if has_target claude; then
    say "  skill      via $CLAUDE_SKILLS (shared)"
  else
    link "$VSCODE_SKILLS/$SKILL_NAME" "$SKILL_SRC"
  fi
fi

if has_target antigravity; then
  say "Antigravity"
  set_block "$AG_RULES" "$RULES"
  link "$AG_SKILLS/$SKILL_NAME" "$SKILL_SRC"
  link "$AG_CLI_SKILLS/$SKILL_NAME" "$SKILL_SRC"
fi

AGENTS=$(printf '%s' "$TARGETS" | tr ',' ' ')
failed=""
for c in $(printf '%s' "$WITH" | tr ',' ' '); do
  # shellcheck disable=SC2086
  component_up "$c" $AGENTS || failed="$failed $c"
done

if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
  say "Backups of changed files: $BACKUP_DIR"
fi
if [ -n "$failed" ]; then
  warn "components not installed:$failed (see messages above)"
fi
say "Done. Check with ./status.sh. In each project run: agent-kit-project init. Undo with ./uninstall.sh"
[ -z "$failed" ]
