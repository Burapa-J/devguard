# shellcheck shell=bash
# rtk — rewrites shell commands and compresses their output before the agent reads it.
# Upstream: https://github.com/rtk-ai/rtk  (Homebrew: rtk)
# Opt-in: it can hide failing lines. verified-dev captures evidence with agent-verify and the
# file-read tool, which rtk does not touch.

rtk_desc() { echo "shell-output compression hook (Homebrew rtk; opt-in)"; }

rtk_present() { command -v rtk >/dev/null 2>&1 && rtk gain >/dev/null 2>&1; }

rtk_install() {
  need brew "Homebrew not found; see https://brew.sh" || return 1
  run brew install rtk
}

rtk_wire() {
  case "$1" in
    claude) run rtk init -g --auto-patch ;;
    vscode) run rtk init -g --copilot ;;
    antigravity) run rtk init -g --agent antigravity ;;
  esac
}

rtk_unwire() {
  case "$1" in
    claude) run rtk init -g --uninstall ;;
    vscode) warn "rtk has no documented unwire for Copilot; remove its hook from ~/.copilot/hooks by hand" ;;
    antigravity)
      if [ -d "$HOME/.gemini/config/plugins/rtk" ]; then
        if [ "$DRY_RUN" = 1 ]; then
          say "  would remove $HOME/.gemini/config/plugins/rtk"
        else
          backup "$HOME/.gemini/config/plugins/rtk"
          rm -rf "$HOME/.gemini/config/plugins/rtk"
          say "  removed    $HOME/.gemini/config/plugins/rtk"
        fi
      fi
      ;;
  esac
}

rtk_remove() { run brew uninstall rtk; }

rtk_status() {
  if [ -f "$HOME/.claude/hooks/rtk-rewrite.sh" ]; then echo "    claude: wired"; else echo "    claude: -"; fi
  echo "    vscode: (not detectable)"
  if [ -d "$HOME/.gemini/config/plugins/rtk" ]; then echo "    antigravity: wired"; else echo "    antigravity: -"; fi
}
