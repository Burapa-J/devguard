#!/usr/bin/env bash
# Show what agent-kit has installed and wired. Read-only.
# shellcheck disable=SC2016
set -u

KIT_DIR=$(cd "$(dirname "$0")" && pwd -P)
DRY_RUN=1
BACKUP_DIR=""
# shellcheck source=lib.sh
. "$KIT_DIR/lib.sh"
# shellcheck source=components/common.sh
. "$KIT_DIR/components/common.sh"
load_components

mark() { if eval "$2"; then echo "  ok   $1"; else echo "  --   $1"; fi; }

echo "Core"
mark "Claude Code rules block      $CLAUDE_RULES" 'has_block "$CLAUDE_RULES"'
mark "VS Code rules block          $VSCODE_RULES" 'has_block "$VSCODE_RULES"'
mark "Antigravity rules block      $AG_RULES" 'has_block "$AG_RULES"'
mark "skill (Claude Code/VS Code)  $CLAUDE_SKILLS/$SKILL_NAME" 'is_ours "$CLAUDE_SKILLS/$SKILL_NAME"'
mark "skill (Antigravity)          $AG_SKILLS/$SKILL_NAME" 'is_ours "$AG_SKILLS/$SKILL_NAME"'
mark "agent-verify                 $VERIFY_LINK" 'is_ours "$VERIFY_LINK"'
mark "agent-kit-project            $PROJECT_LINK" 'is_ours "$PROJECT_LINK"'
mark "compaction hook              $CLAUDE_SETTINGS" '[ -f "$CLAUDE_SETTINGS" ] && grep -qF "$HOOK_CMD" "$CLAUDE_SETTINGS"'
mark "auto project setup hook   $AUTO_ROOTS" '[ -f "$AUTO_ROOTS" ] && grep -qF "$AUTO_HOOK_CMD" "$CLAUDE_SETTINGS" 2>/dev/null'
[ -f "$AUTO_ROOTS" ] && sed 's/^/         root: /' "$AUTO_ROOTS"
mark "\$HOME/.local/bin on PATH" 'case ":$PATH:" in *":$HOME/.local/bin:"*) true ;; *) false ;; esac'

echo
echo "Components"
for c in $ALL_COMPONENTS; do
  f=$(fn_name "$c")
  managed="not managed"
  [ -d "$(state_dir "$c")" ] && managed="managed by agent-kit (wired: $(state_wired "$c" | tr '\n' ' '))"
  if "${f}_present"; then cli="CLI installed"; else cli="CLI missing"; fi
  echo "  $c: $cli, $managed"
  "${f}_status"
done

if command -v tokless >/dev/null 2>&1; then
  echo
  echo "Note: tokless is still installed (run 'tokless uninstall' to avoid duplicate wiring)."
fi
