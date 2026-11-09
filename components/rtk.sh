# shellcheck shell=bash
# rtk — rewrites shell commands and compresses their output before the agent reads it.
# Upstream: https://github.com/rtk-ai/rtk  (Homebrew: rtk)
# Safe alongside verified-dev: verification evidence is captured with agent-verify and read with the
# file-read tool, which rtk does not touch.

rtk_desc() { echo "shell-output compression hook (Homebrew rtk)"; }

rtk_present() { command -v rtk >/dev/null 2>&1 && rtk gain >/dev/null 2>&1; }

rtk_asset() {
  local arch="x86_64"
  case "$(uname -m)" in arm64 | aarch64) arch="aarch64" ;; esac
  if is_windows; then
    echo "rtk-${arch}-pc-windows-msvc.zip"
  elif [ "$(uname -s)" = Darwin ]; then
    echo "rtk-${arch}-apple-darwin.tar.gz"
  elif [ "$(uname -s)" = Linux ]; then
    [ "$arch" = aarch64 ] && echo "rtk-aarch64-unknown-linux-gnu.tar.gz" || echo "rtk-x86_64-unknown-linux-musl.tar.gz"
  fi
}

rtk_install_prebuilt() {
  local asset url tmp
  asset=$(rtk_asset)
  [ -n "$asset" ] || return 1
  url="${RTK_RELEASE_BASE_URL:-https://github.com/rtk-ai/rtk/releases/latest/download}/$asset"
  if [ "$DRY_RUN" = 1 ]; then
    say "  would download $url -> $HOME/.local/bin"
    return 0
  fi
  say "  downloading $asset -> $HOME/.local/bin"
  mkdir -p "$HOME/.local/bin"
  tmp=$(mktemp -d)
  if ! curl -fsSL "$url" -o "$tmp/$asset"; then
    rm -rf "$tmp"
    return 1
  fi
  case "$asset" in
    *.zip)
      if command -v unzip >/dev/null 2>&1; then
        unzip -qo "$tmp/$asset" -d "$HOME/.local/bin" || { rm -rf "$tmp"; return 1; }
      elif command -v powershell.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
        powershell.exe -NoProfile -Command "Expand-Archive -Force -Path '$(cygpath -w "$tmp/$asset")' -DestinationPath '$(cygpath -w "$HOME/.local/bin")'" >/dev/null || { rm -rf "$tmp"; return 1; }
      else
        rm -rf "$tmp"
        return 1
      fi
      ;;
    *.tar.gz)
      tar -xzf "$tmp/$asset" -C "$HOME/.local/bin" || { rm -rf "$tmp"; return 1; }
      chmod +x "$HOME/.local/bin/rtk" 2>/dev/null || true
      ;;
  esac
  rm -rf "$tmp"
  [ -x "$HOME/.local/bin/rtk" ] || [ -x "$HOME/.local/bin/rtk.exe" ]
}

rtk_install() {
  if command -v brew >/dev/null 2>&1 && ! is_windows; then
    run brew install rtk || return 1
  else
    rtk_install_prebuilt || { warn "rtk install failed; install Homebrew or download from https://github.com/rtk-ai/rtk/releases"; return 1; }
  fi
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
        if [ "$DRY_RUN" = 1 ]; then
          say "  would remove $HOME/.copilot/hooks/rtk-rewrite.json"
        else
          rm -f "$HOME/.copilot/hooks/rtk-rewrite.json"
          rmdir "$HOME/.copilot/hooks" 2>/dev/null || true
          say "  removed    $HOME/.copilot/hooks/rtk-rewrite.json"
        fi
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

rtk_remove() {
  if [ -f "$HOME/.local/bin/rtk.exe" ] || { [ -f "$HOME/.local/bin/rtk" ] && [ ! -L "$HOME/.local/bin/rtk" ]; }; then
    if [ "$DRY_RUN" = 1 ]; then
      say "  would remove $HOME/.local/bin/rtk"
    else
      rm -f "$HOME/.local/bin/rtk" "$HOME/.local/bin/rtk.exe"
      say "  removed    $HOME/.local/bin/rtk"
    fi
  elif command -v brew >/dev/null 2>&1; then
    run brew uninstall rtk
  fi
}

rtk_status() {
  if [ -f "$HOME/.claude/hooks/rtk-rewrite.sh" ] || grep -q "rtk hook claude" "$CLAUDE_SETTINGS" 2>/dev/null; then
    echo "    claude: wired"
  else
    echo "    claude: -"
  fi
  if [ -f "$HOME/.copilot/hooks/rtk-rewrite.json" ]; then echo "    vscode: wired"; else echo "    vscode: (not detectable)"; fi
  if [ -d "$HOME/.gemini/config/plugins/rtk" ]; then echo "    antigravity: wired"; else echo "    antigravity: -"; fi
}
