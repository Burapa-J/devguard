# shellcheck shell=bash
# context-mode — sandboxed execution and indexed search that keep large outputs out of context.
# Upstream: https://github.com/mksglu/context-mode  (npm: context-mode, needs Node >= 22.5)
# MCP-only wiring (no hooks). The Claude Code plugin adds hooks; install that yourself if wanted.

CONTEXT_MODE_VERSION=1.0.169

context_mode_desc() { echo "sandboxed output + search via MCP (npm context-mode@$CONTEXT_MODE_VERSION; opt-in)"; }

context_mode_present() { command -v context-mode >/dev/null 2>&1; }

context_mode_pinned_version() { echo "$CONTEXT_MODE_VERSION"; }

context_mode_installed_version() {
  npm ls -g context-mode --depth=0 2>/dev/null | sed -n 's/.*context-mode@\([0-9.a-zA-Z_-]*\).*/\1/p' | head -n 1
}

context_mode_install() {
  local major
  need node "Node.js not found; install it first (brew install node)" || return 1
  major=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)
  if [ "$major" -lt 22 ]; then
    warn "context-mode needs Node >= 22.5 (found $(node -v 2>/dev/null))"
    return 1
  fi
  run npm install -g "context-mode@$CONTEXT_MODE_VERSION"
}

context_mode_wire() { mcp_set "$1" context-mode '{"command":"context-mode"}'; }

context_mode_unwire() { mcp_del "$1" context-mode; }

context_mode_remove() { run npm uninstall -g context-mode; }

context_mode_status() {
  local a
  for a in claude vscode antigravity; do
    if mcp_has "$a" context-mode; then echo "    $a: wired"; else echo "    $a: -"; fi
  done
}
