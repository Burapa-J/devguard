#!/usr/bin/env bash
# Remove everything agent-kit installed, and nothing else: the marked rules blocks, symlinks
# pointing into this kit, the hook entry with this kit's path, and component wiring agent-kit added.
# Tool CLIs stay installed unless --purge, and --purge only removes CLIs agent-kit installed.
set -eu

KIT_DIR=$(cd "$(dirname "$0")" && pwd -P)
DRY_RUN=0
PURGE=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --purge) PURGE=1 ;;
    -h | --help) echo "Usage: ./uninstall.sh [--dry-run] [--purge]"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 64 ;;
  esac
done

BACKUP_DIR=""
[ "$DRY_RUN" = 1 ] || BACKUP_DIR="$HOME/.agent-kit-backup/uninstall-$(date +%Y%m%d-%H%M%S)"

# shellcheck source=lib.sh
. "$KIT_DIR/lib.sh"
# shellcheck source=components/common.sh
. "$KIT_DIR/components/common.sh"
load_components

[ "$DRY_RUN" = 1 ] && say "Dry run: nothing will be changed."

for c in $ALL_COMPONENTS; do
  [ -d "$(state_dir "$c")" ] && component_down "$c" "$PURGE"
done

for f in "$CLAUDE_RULES" "$VSCODE_RULES" "$AG_RULES" "$OPENCODE_RULES" "$CURSOR_RULES" $LEGACY_CURSOR_RULES "$CODEX_RULES"; do
  remove_block "$f"
done

for l in $LEGACY_LINKS "$CLI_LINK" "$VERIFY_LINK" "$PROJECT_LINK" \
         "$CLAUDE_SKILLS/$SKILL_NAME" "$VSCODE_SKILLS/$SKILL_NAME" \
         "$AG_SKILLS/$SKILL_NAME" "$AG_CLI_SKILLS/$SKILL_NAME" \
         "$OPENCODE_SKILLS/$SKILL_NAME" "$CURSOR_SKILLS/$SKILL_NAME" \
         "$CODEX_SKILLS/$SKILL_NAME" "$GEMINI_SKILLS/$SKILL_NAME"; do
  unlink_ours "$l"
done

if [ -f "$CLAUDE_SETTINGS" ] && grep -qF "$HOOK_CMD" "$CLAUDE_SETTINGS"; then
  edit_settings "$JQ_REMOVE_HOOK"
fi
if [ -f "$CLAUDE_SETTINGS" ] && grep -qF "$AUTO_HOOK_CMD" "$CLAUDE_SETTINGS"; then
  edit_settings "$JQ_REMOVE_HOOK" "$AUTO_HOOK_CMD"
fi
zsh_hook_remove
launchd_remove
if [ -e "$AUTO_ROOTS" ] || [ -d "$STATE_DIR/logs" ] || [ -d "$STATE_DIR/locks" ] || [ -e "$STATE_DIR/device-id" ]; then
  if [ "$DRY_RUN" = 1 ]; then
    say "  would remove automatic project setup ($AUTO_ROOTS, logs)"
  else
    rm -rf "$AUTO_ROOTS" "$STATE_DIR/logs" "$STATE_DIR/locks" "$STATE_DIR/device-id"
    rmdir "$STATE_DIR" 2>/dev/null || true
    say "  removed    automatic project setup"
  fi
fi

# Directories install may have created. rmdir only succeeds on empty ones, deepest first.
if [ "$DRY_RUN" = 0 ]; then
  for d in "$CLAUDE_SKILLS" "$VSCODE_SKILLS" "$HOME/.copilot" \
           "$AG_SKILLS" "$HOME/.gemini/config" "$AG_CLI_SKILLS" "$HOME/.gemini/antigravity-cli" \
           "$GEMINI_SKILLS" "$HOME/.gemini/antigravity" "$HOME/.gemini" \
           "$OPENCODE_SKILLS" "$HOME/.config/opencode" \
           "$CURSOR_SKILLS" "$(dirname "$CURSOR_RULES")" "$HOME/.cursor" \
           "$CODEX_SKILLS" "$HOME/.codex" \
           "$(dirname "$VSCODE_MCP")" "$(dirname "$(dirname "$VSCODE_MCP")")" "$HOME/.config" \
           "${AGENT_KIT_LAUNCHD_DIR:-}" \
           "$HOME/.local/bin" "$HOME/.local/share" "$HOME/.local"; do
    [ -d "$d" ] && rmdir "$d" 2>/dev/null && say "  rmdir      $d"
  done
fi

if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
  say "Backups of changed files: $BACKUP_DIR"
  prune_backups
fi
say "Done."
