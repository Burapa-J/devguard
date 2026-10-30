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

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_OK=$'\033[32m' C_OFF=$'\033[90m' C_WARN=$'\033[33m' C_BOLD=$'\033[1m' C_RESET=$'\033[0m'
else
  C_OK="" C_OFF="" C_WARN="" C_BOLD="" C_RESET=""
fi

cell() {
  if eval "$1"; then
    printf "${C_OK}%-10s${C_RESET}" "✓ ${2:-wired}"
  else
    printf "${C_OFF}%-10s${C_RESET}" "○ ${3:-off}"
  fi
}

rtk_wired() {
  case "$1" in
    claude) [ -f "$HOME/.claude/hooks/rtk-rewrite.sh" ] || grep -q "rtk hook claude" "$CLAUDE_SETTINGS" 2>/dev/null ;;
    vscode) [ -f "$HOME/.copilot/hooks/rtk-rewrite.json" ] ;;
    antigravity) [ -d "$HOME/.gemini/config/plugins/rtk" ] ;;
    opencode) [ -f "$HOME/.config/opencode/plugins/rtk.ts" ] || [ -f "$HOME/.config/opencode/plugins/tokless-rtk.ts" ] ;;
    cursor) [ -f "$HOME/.cursor/hooks.json" ] && grep -q "rtk" "$HOME/.cursor/hooks.json" 2>/dev/null ;;
    codex) [ -f "$HOME/.codex/hooks.json" ] && grep -q "rtk" "$HOME/.codex/hooks.json" 2>/dev/null ;;
    gemini) [ -f "$HOME/.gemini/hooks/rtk-hook-gemini.sh" ] ;;
  esac
}

echo "${C_BOLD}╭─ devguard overview ────────────────────────────────────────────────────────────╮${C_RESET}"
printf "${C_BOLD}│ %-18s %-10s %-10s %-10s %-10s %-10s %-8s │${C_RESET}\n" \
  "Agent" "Rules" "Skill" "codegraph" "projectmem" "rtk" "ctx-mode"
echo "├────────────────────────────────────────────────────────────────────────────────┤"
printf "│ %-18s %s %s %s %s %s %s│\n" "Claude Code" \
  "$(cell 'has_block "$CLAUDE_RULES"' ok --)" \
  "$(cell 'is_ours "$CLAUDE_SKILLS/$SKILL_NAME"' ok --)" \
  "$(cell 'mcp_has claude codegraph')" \
  "$(cell 'mcp_has claude projectmem')" \
  "$(cell 'rtk_wired claude' on off)" \
  "$(cell 'mcp_has claude context-mode')"
printf "│ %-18s %s %s %s %s %s %s│\n" "VS Code (Copilot)" \
  "$(cell 'has_block "$VSCODE_RULES"' ok --)" \
  "$(cell 'is_ours "$CLAUDE_SKILLS/$SKILL_NAME" || is_ours "$VSCODE_SKILLS/$SKILL_NAME"' ok --)" \
  "$(cell 'mcp_has vscode codegraph')" \
  "$(cell 'mcp_has vscode projectmem')" \
  "$(cell 'rtk_wired vscode' on off)" \
  "$(cell 'mcp_has vscode context-mode')"
printf "│ %-18s %s %s %s %s %s %s│\n" "Antigravity" \
  "$(cell 'has_block "$AG_RULES"' ok --)" \
  "$(cell 'is_ours "$AG_SKILLS/$SKILL_NAME"' ok --)" \
  "$(cell 'mcp_has antigravity codegraph')" \
  "$(cell 'mcp_has antigravity projectmem')" \
  "$(cell 'rtk_wired antigravity' on off)" \
  "$(cell 'mcp_has antigravity context-mode')"
if [ -d "$HOME/.config/opencode" ] || has_block "$OPENCODE_RULES"; then
  printf "│ %-18s %s %s %s %s %s %s│\n" "OpenCode" \
    "$(cell 'has_block "$OPENCODE_RULES"' ok --)" \
    "$(cell 'is_ours "$OPENCODE_SKILLS/$SKILL_NAME"' ok --)" \
    "$(cell 'mcp_has opencode codegraph')" \
    "$(cell 'mcp_has opencode projectmem')" \
    "$(cell 'rtk_wired opencode' on off)" \
    "$(cell 'mcp_has opencode context-mode')"
fi
if [ -d "$HOME/.cursor" ] || has_block "$CURSOR_RULES"; then
  printf "│ %-18s %s %s %s %s %s %s│\n" "Cursor" \
    "$(cell 'has_block "$CURSOR_RULES"' ok --)" \
    "$(cell 'is_ours "$CURSOR_SKILLS/$SKILL_NAME"' ok --)" \
    "$(cell 'mcp_has cursor codegraph')" \
    "$(cell 'mcp_has cursor projectmem')" \
    "$(cell 'rtk_wired cursor' on off)" \
    "$(cell 'mcp_has cursor context-mode')"
fi
if [ -d "$HOME/.codex" ] || has_block "$CODEX_RULES"; then
  printf "│ %-18s %s %s %s %s %s %s│\n" "Codex CLI" \
    "$(cell 'has_block "$CODEX_RULES"' ok --)" \
    "$(cell 'is_ours "$CODEX_SKILLS/$SKILL_NAME"' ok --)" \
    "$(cell 'mcp_has codex codegraph')" \
    "$(cell 'mcp_has codex projectmem')" \
    "$(cell 'rtk_wired codex' on off)" \
    "$(cell 'mcp_has codex context-mode')"
fi
if is_ours "$GEMINI_SKILLS/$SKILL_NAME" || [ -f "$HOME/.gemini/hooks/rtk-hook-gemini.sh" ]; then
  printf "│ %-18s %s %s %s %s %s %s│\n" "Gemini CLI" \
    "$(cell 'has_block "$AG_RULES"' ok --)" \
    "$(cell 'is_ours "$GEMINI_SKILLS/$SKILL_NAME"' ok --)" \
    "$(cell 'mcp_has gemini codegraph')" \
    "$(cell 'mcp_has gemini projectmem')" \
    "$(cell 'rtk_wired gemini' on off)" \
    "$(cell 'mcp_has gemini context-mode')"
fi
echo "${C_BOLD}╰────────────────────────────────────────────────────────────────────────────────╯${C_RESET}"

flag() { if eval "$2"; then printf "${C_OK}✓${C_RESET} %s  " "$1"; else printf "${C_WARN}!${C_RESET} %s  " "$1"; fi; }
printf "  Tools        "
flag "ast-grep" 'command -v ast-grep >/dev/null 2>&1'
flag "xcbeautify" 'command -v xcbeautify >/dev/null 2>&1'
flag "shellcheck" 'command -v shellcheck >/dev/null 2>&1'
flag "agent-verify" 'is_ours "$VERIFY_LINK"'
echo
if projectmem_present; then
  stale_mcp=$(projectmem_stale_mcp_pids | tr '\n' ' ' | sed 's/ $//')
  printf "  Memory sync  "
  flag "hook" 'projectmem_sync_hook_ok'
  flag "iCloud hub" '[ -d "$(projectmem_sync_hub)" ]'
  flag "$(projectmem_sync_devices | wc -l | tr -d ' ') device(s)" '[ -n "$(projectmem_sync_devices)" ]'
  sync_summary=$("$PROJECTMEM_VENV/bin/python" "$KIT_DIR/bin/pjm_sync.py" --check-summary 2>/dev/null)
  # shellcheck disable=SC2034  # read inside the eval'd flag/mark conditions
  sync_rc=$?
  [ -n "$sync_summary" ] && flag "$sync_summary" '[ "$sync_rc" = 0 ]'
  if [ -z "$stale_mcp" ]; then flag "MCP up to date" true; else flag "restart agents (MCP on old code)" false; fi
  echo
fi
echo

mark() { if eval "$2"; then echo "  ${C_OK}ok${C_RESET}   $1"; else echo "  ${C_OFF}--${C_RESET}   $1"; fi; }

echo "Core"
mark "Claude Code rules block      $CLAUDE_RULES" 'has_block "$CLAUDE_RULES"'
mark "VS Code rules block          $VSCODE_RULES" 'has_block "$VSCODE_RULES"'
mark "Antigravity rules block      $AG_RULES" 'has_block "$AG_RULES"'
mark "skill (Claude Code/VS Code)  $CLAUDE_SKILLS/$SKILL_NAME" 'is_ours "$CLAUDE_SKILLS/$SKILL_NAME"'
mark "skill (Antigravity)          $AG_SKILLS/$SKILL_NAME" 'is_ours "$AG_SKILLS/$SKILL_NAME"'
mark "agent-verify                 $VERIFY_LINK" 'is_ours "$VERIFY_LINK"'
mark "devguard-project             $PROJECT_LINK" 'is_ours "$PROJECT_LINK"'
mark "compaction hook              $CLAUDE_SETTINGS" '[ -f "$CLAUDE_SETTINGS" ] && grep -qF "$HOOK_CMD" "$CLAUDE_SETTINGS"'
mark "auto setup (Claude Code)     $AUTO_ROOTS" '[ -f "$AUTO_ROOTS" ] && grep -qF "$AUTO_HOOK_CMD" "$CLAUDE_SETTINGS" 2>/dev/null'
[ -f "$AUTO_ROOTS" ] && sed 's/^/         root: /' "$AUTO_ROOTS"
mark "auto setup on cd (zsh)       $ZSHRC" '[ -f "$ZSHRC" ] && grep -qxF "$ZSH_BEGIN" "$ZSHRC"'
if use_launchd; then
  mark "auto setup scan (launchd)    $LAUNCHD_PLIST" '[ -f "$LAUNCHD_PLIST" ]'
fi
mark "devguard command             $CLI_LINK" 'is_ours "$CLI_LINK"'
mark "\$HOME/.local/bin on PATH" 'case ":$PATH:" in *":$HOME/.local/bin:"*) true ;; *) false ;; esac'

echo
echo "Components"
for c in $ALL_COMPONENTS; do
  f=$(fn_name "$c")
  managed="not managed"
  [ -d "$(state_dir "$c")" ] && managed="managed by devguard (wired: $(state_wired "$c" | tr '\n' ' '))"
  if "${f}_present"; then cli="CLI installed"; else cli="CLI missing"; fi
  echo "  $c: $cli, $managed"
done

if projectmem_present; then
  echo
  echo "Memory sync"
  hub=$(projectmem_sync_hub)
  this_dev=$(cat "$STATE_DIR/device-id" 2>/dev/null || true)
  mark "sync hook (.pth)             $(projectmem_sync_pth)" 'projectmem_sync_hook_ok'
  mark "iCloud hub                   $hub" '[ -d "$hub" ]'
  if [ -d "$hub" ]; then
    echo "         projects: $(find "$hub/projects" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
    projectmem_sync_devices | while IFS= read -r d; do
      if [ "$d" = "$this_dev" ]; then echo "         device: $d (this Mac)"; else echo "         device: $d"; fi
    done
  fi
  [ -n "${sync_summary:-}" ] && mark "projects: $sync_summary (details: devguard sync --check)" '[ "$sync_rc" = 0 ]'
  if [ -n "$stale_mcp" ]; then
    echo "  ${C_WARN}!!${C_RESET}   MCP servers running old sync code (pid $stale_mcp): restart your agents"
  else
    mark "projectmem MCP servers up to date" true
  fi
fi

echo
echo "Companion Tools"
if command -v ast-grep >/dev/null 2>&1; then
  sg_ver=$(ast-grep --version 2>/dev/null | awk '{print $2}')
  mark "$(printf '%-28s %s' "ast-grep ${sg_ver:-}" "$(command -v ast-grep)")" true
else
  mark "ast-grep                     (not installed; brew install ast-grep)" false
fi
if command -v shellcheck >/dev/null 2>&1; then
  sc_ver=$(shellcheck --version 2>/dev/null | awk '/^version:/ {print $2}')
  mark "$(printf '%-28s %s' "shellcheck ${sc_ver:-}" "$(command -v shellcheck)")" true
else
  mark "shellcheck                   (not installed; brew install shellcheck)" false
fi
if command -v xcbeautify >/dev/null 2>&1; then
  xcb_ver=$(xcbeautify --version 2>/dev/null | head -n 1)
  mark "$(printf '%-28s %s' "xcbeautify ${xcb_ver:-}" "$(command -v xcbeautify)")" true
else
  mark "xcbeautify                   (not installed; brew install xcbeautify)" false
fi

if command -v tokless >/dev/null 2>&1; then
  echo
  echo "Note: tokless is still installed (run 'tokless uninstall' to avoid duplicate wiring)."
fi
