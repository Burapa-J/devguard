# shellcheck shell=bash
# rtk — rewrites shell commands and compresses their output before the agent reads it.
# Upstream: https://github.com/rtk-ai/rtk  (Homebrew: rtk)
# Safe alongside verified-dev: verification evidence is captured with agent-verify and read with the
# file-read tool, which rtk does not touch.

rtk_desc() { echo "shell-output compression hook (Homebrew rtk)"; }

rtk_present() { command -v rtk >/dev/null 2>&1 && rtk gain >/dev/null 2>&1; }

rtk_install() {
  need brew "Homebrew not found; see https://brew.sh" || return 1
  run brew install rtk || return 1
  [ "$DRY_RUN" = 1 ] || rtk telemetry disable >/dev/null 2>&1 || true
}

rtk_wire() {
  [ "$DRY_RUN" = 1 ] || rtk telemetry disable >/dev/null 2>&1 || true
  case "$1" in
    claude) run rtk init -g --auto-patch ;;
    vscode) run rtk init -g --copilot ;;
    antigravity) run rtk init -g --agent antigravity ;;
    opencode) run rtk init -g --opencode --no-patch ;;
    cursor) run rtk init -g --agent=cursor ;;
    codex)
      run rtk init -g --codex
      [ -f "$KIT_DIR/rules/core.md" ] && set_block "$CODEX_RULES" "$KIT_DIR/rules/core.md" >/dev/null
      ;;
    gemini)
      run rtk init -g --gemini --hook-only --auto-patch
      [ -f "$KIT_DIR/rules/core.md" ] && set_block "$AG_RULES" "$KIT_DIR/rules/core.md" >/dev/null
      ;;
  esac
}

rtk_unwire() {
  case "$1" in
    claude) run rtk init -g --uninstall ;;
    vscode)
      if [ -f "$HOME/.copilot/hooks/rtk-rewrite.json" ]; then
        [ "$DRY_RUN" = 1 ] && say "  would remove $HOME/.copilot/hooks/rtk-rewrite.json" || {
          rm -f "$HOME/.copilot/hooks/rtk-rewrite.json"
          rmdir "$HOME/.copilot/hooks" 2>/dev/null || true
          say "  removed    $HOME/.copilot/hooks/rtk-rewrite.json"
        }
      fi
      ;;
    antigravity)
      run rtk init -g --agent antigravity --uninstall
      [ "$DRY_RUN" = 1 ] || rmdir "$HOME/.gemini/config/plugins" "$HOME/.gemini/config" "$HOME/.gemini" 2>/dev/null || true
      ;;
    opencode) run rtk init -g --opencode --uninstall ;;
    cursor) run rtk init -g --agent=cursor --uninstall ;;
    codex) run rtk init -g --codex --uninstall ;;
    gemini) run rtk init -g --gemini --uninstall ;;
  esac
}

rtk_remove() { run brew uninstall rtk; }

rtk_status() {
  if [ -f "$HOME/.claude/hooks/rtk-rewrite.sh" ] || grep -q "rtk hook claude" "$CLAUDE_SETTINGS" 2>/dev/null; then
    echo "    claude: wired"
  else
    echo "    claude: -"
  fi
  if [ -f "$HOME/.copilot/hooks/rtk-rewrite.json" ]; then echo "    vscode: wired"; else echo "    vscode: (not detectable)"; fi
  if [ -d "$HOME/.gemini/config/plugins/rtk" ]; then echo "    antigravity: wired"; else echo "    antigravity: -"; fi
}
