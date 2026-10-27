#!/usr/bin/env bash
# Remove everything agent-kit installed, and nothing else:
# only the marked rules blocks, symlinks pointing into this kit, and the hook entry with this kit's path.
set -eu

KIT_DIR=$(cd "$(dirname "$0")" && pwd -P)
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h | --help) echo "Usage: ./uninstall.sh [--dry-run]"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 64 ;;
  esac
done

BACKUP_DIR=""
[ "$DRY_RUN" = 1 ] || BACKUP_DIR="$HOME/.agent-kit-backup/uninstall-$(date +%Y%m%d-%H%M%S)"

# shellcheck source=lib.sh
. "$KIT_DIR/lib.sh"

[ "$DRY_RUN" = 1 ] && say "Dry run: nothing will be changed."

for f in "$CLAUDE_RULES" "$VSCODE_RULES" "$AG_RULES"; do
  remove_block "$f"
done

for l in "$VERIFY_LINK" \
         "$CLAUDE_SKILLS/$SKILL_NAME" "$VSCODE_SKILLS/$SKILL_NAME" \
         "$AG_SKILLS/$SKILL_NAME" "$AG_CLI_SKILLS/$SKILL_NAME"; do
  unlink_ours "$l"
done

if [ -f "$CLAUDE_SETTINGS" ] && grep -qF "$HOOK_CMD" "$CLAUDE_SETTINGS"; then
  edit_settings "$JQ_REMOVE_HOOK"
fi

# Directories install may have created. rmdir only succeeds on empty ones, deepest first.
if [ "$DRY_RUN" = 0 ]; then
  for d in "$CLAUDE_SKILLS" "$VSCODE_SKILLS" "$HOME/.copilot" \
           "$AG_SKILLS" "$HOME/.gemini/config" "$AG_CLI_SKILLS" "$HOME/.gemini/antigravity-cli" \
           "$HOME/.local/bin" "$HOME/.local"; do
    [ -d "$d" ] && rmdir "$d" 2>/dev/null && say "  rmdir      $d"
  done
fi

if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
  say "Backups of changed files: $BACKUP_DIR"
fi
say "Done."
