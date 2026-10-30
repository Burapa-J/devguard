#!/usr/bin/env bash
# Install agent-kit: rules, skill, agent-verify, hooks, tool components and automatic project setup.
# With no options it does the recommended setup; see --help.
# Safe to re-run: every step is idempotent, and changed files are backed up first.
set -eu

KIT_DIR=$(cd "$(dirname "$0")" && pwd -P)
TARGETS="claude,vscode,antigravity"
WITH_HOOKS=1
DRY_RUN=0
WITH=""
AUTO_PROJECT=""

usage() {
  cat <<EOF
Usage: ./install.sh [options]

With no options: rules + skill for Claude Code, VS Code and Antigravity, the compaction
hook, codegraph + projectmem + rtk, and automatic setup of repositories under ~/Developer.

  --dry-run            Show what would change; change nothing.
  --no-hooks           Skip the Claude Code compaction-reminder hook.
  --with=LIST          Tool components, comma-separated, or "none".
                       Available: codegraph, projectmem, rtk, context-mode.
                       Default: codegraph,projectmem,rtk
  --targets=LIST       Subset of: claude, vscode, antigravity, opencode, cursor, codex, gemini
                       (default: claude,vscode,antigravity).
  --auto-project=DIRS  Folders whose git repositories are set up automatically
                       (comma-separated). Default: ~/Developer if it exists, or the
                       folders from the previous install. "none" turns it off.
                       A repo containing .agent-kit-skip is never touched. Setup is
                       triggered by Claude Code session start, cd in zsh, and a
                       30-minute launchd scan (macOS), so VS Code and Antigravity
                       are covered too.

Quit Claude Code, VS Code and Antigravity before installing: they rewrite their own
config files and can overwrite changes made while they run.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --with-hooks) WITH_HOOKS=1 ;;
    --no-hooks) WITH_HOOKS=0 ;;
    --with=*) WITH=${arg#--with=} ;;
    --targets=*) TARGETS=${arg#--targets=} ;;
    --auto-project=*) AUTO_PROJECT=${arg#--auto-project=} ;;
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

# Default: keep the previous roots, else ~/Developer when it exists.
if [ -z "$AUTO_PROJECT" ]; then
  if [ -f "$AUTO_ROOTS" ]; then
    AUTO_PROJECT=keep
  elif [ -d "$HOME/Developer" ]; then
    AUTO_PROJECT="$HOME/Developer"
  else
    AUTO_PROJECT=none
  fi
fi

ROOTS_TMP=""
if [ "$AUTO_PROJECT" = keep ]; then
  ROOTS_TMP=$(mktemp)
  cat "$AUTO_ROOTS" > "$ROOTS_TMP"
elif [ "$AUTO_PROJECT" != none ]; then
  ROOTS_TMP=$(mktemp)
  old_ifs=$IFS; IFS=,
  for d in $AUTO_PROJECT; do
    IFS=$old_ifs
    case "$d" in "~"*) d="$HOME${d#\~}" ;; esac
    [ -d "$d" ] || { echo "--auto-project: '$d' is not a directory" >&2; rm -f "$ROOTS_TMP"; exit 64; }
    (cd "$d" && pwd -P) >> "$ROOTS_TMP"
  done
  IFS=$old_ifs
fi

RULES="$KIT_DIR/rules/core.md"
SKILL_SRC="$KIT_DIR/skills/$SKILL_NAME"

[ "$DRY_RUN" = 1 ] && say "Dry run: nothing will be changed."
[ "$DRY_RUN" = 1 ] || chmod +x "$KIT_DIR/bin/devguard" "$KIT_DIR/bin/doctor.sh" "$KIT_DIR/bin/verify.sh" "$KIT_DIR/bin/project.sh" "$KIT_DIR/bin/stats.sh" "$KIT_DIR/bin/ui.sh" "$KIT_DIR/bin/pjm_sync.py" "$KIT_DIR/hooks/remind.sh"

if command -v tokless >/dev/null 2>&1; then
  warn "tokless is installed. It wires some of the same tools; run 'tokless uninstall' first to avoid duplicates."
fi

say "Commands: devguard, agent-verify, devguard-project"
for old_link in $LEGACY_LINKS; do
  unlink_ours "$old_link"
done
link "$CLI_LINK" "$KIT_DIR/bin/devguard"
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

if has_target opencode; then
  say "OpenCode"
  set_block "$OPENCODE_RULES" "$RULES"
  link "$OPENCODE_SKILLS/$SKILL_NAME" "$SKILL_SRC"
fi

if has_target cursor; then
  say "Cursor"
  for old_cr in $LEGACY_CURSOR_RULES; do
    remove_block "$old_cr"
  done
  set_block "$CURSOR_RULES" "$RULES"
  link "$CURSOR_SKILLS/$SKILL_NAME" "$SKILL_SRC"
fi

if has_target codex; then
  say "Codex CLI"
  set_block "$CODEX_RULES" "$RULES"
  link "$CODEX_SKILLS/$SKILL_NAME" "$SKILL_SRC"
fi

if has_target gemini; then
  say "Gemini CLI"
  set_block "$AG_RULES" "$RULES"
  link "$GEMINI_SKILLS/$SKILL_NAME" "$SKILL_SRC"
fi

if [ "$AUTO_PROJECT" != none ]; then
  say "Automatic project setup ($(tr '\n' ';' < "$ROOTS_TMP" | sed 's/;$//'))"
  if [ -f "$AUTO_ROOTS" ] && cmp -s "$ROOTS_TMP" "$AUTO_ROOTS"; then
    say "  unchanged  $AUTO_ROOTS"
  elif [ "$DRY_RUN" = 1 ]; then
    say "  would write $AUTO_ROOTS"
  else
    mkdir -p "$(dirname "$AUTO_ROOTS")"
    cat "$ROOTS_TMP" > "$AUTO_ROOTS"
    say "  updated    $AUTO_ROOTS"
  fi
  rm -f "$ROOTS_TMP"
  if has_target claude; then edit_settings "$JQ_ADD_HOOK" "$AUTO_HOOK_CMD" startup; fi
  zsh_hook_set
  launchd_set
elif [ -f "$AUTO_ROOTS" ]; then
  say "Automatic project setup: off"
  if [ -f "$CLAUDE_SETTINGS" ] && grep -qF "$AUTO_HOOK_CMD" "$CLAUDE_SETTINGS"; then
    edit_settings "$JQ_REMOVE_HOOK" "$AUTO_HOOK_CMD"
  fi
  zsh_hook_remove
  launchd_remove
  if [ "$DRY_RUN" = 1 ]; then say "  would remove $AUTO_ROOTS"; else rm -f "$AUTO_ROOTS"; say "  removed    $AUTO_ROOTS"; fi
fi

AGENTS=$(printf '%s' "$TARGETS" | tr ',' ' ')
failed=""
for c in $(printf '%s' "$WITH" | tr ',' ' '); do
  # shellcheck disable=SC2086
  component_up "$c" $AGENTS || failed="$failed $c"
done

if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
  say "Backups of changed files: $BACKUP_DIR"
  prune_backups
fi
if [ -n "$failed" ]; then
  warn "components not installed:$failed (see messages above)"
fi
say "Done. Restart your agents and open a new terminal. Check with: devguard status"
if [ "$AUTO_PROJECT" != none ] && [ "$DRY_RUN" = 0 ]; then
  say "Existing repositories get set up by the periodic scan, or right now with: devguard init --all"
fi
[ -z "$failed" ]
