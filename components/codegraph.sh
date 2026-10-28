# shellcheck shell=bash
# codegraph — indexed code graph (supports Swift and ObjC), MCP tool `codegraph_explore`.
# Upstream: https://github.com/colbymchenry/codegraph
# Wiring is delegated to codegraph's own installer: it writes the MCP entry, a marked CLAUDE.md
# section, a UserPromptSubmit hook and auto-allow permissions, and `codegraph uninstall` removes them.

CODEGRAPH_VERSION=1.6.2

codegraph_desc() { echo "code graph search via MCP (npm @colbymchenry/codegraph@$CODEGRAPH_VERSION)"; }

codegraph_present() { command -v codegraph >/dev/null 2>&1; }

codegraph_install() {
  need npm "npm not found; install Node.js first (brew install node)" || return 1
  run npm install -g "@colbymchenry/codegraph@$CODEGRAPH_VERSION" || return 1
  [ "$DRY_RUN" = 1 ] || CODEGRAPH_TELEMETRY=0 codegraph telemetry off >/dev/null 2>&1 || true
}

codegraph_target() {
  case "$1" in
    claude) echo claude ;;
    vscode) echo copilot-vscode ;;
    antigravity) echo antigravity ;;
    opencode) echo opencode ;;
    cursor) echo cursor ;;
    codex) echo codex ;;
    gemini) echo gemini ;;
  esac
}

codegraph_wire() {
  CODEGRAPH_TELEMETRY=0 run codegraph install --target="$(codegraph_target "$1")" --location=global --yes
}

codegraph_unwire() {
  # Upstream uninstall is all-or-nothing across agents; --keep-cli leaves the binary.
  # Run it once per teardown, on the first agent.
  [ "${CODEGRAPH_UNWIRED:-0}" = 1 ] && return 0
  CODEGRAPH_UNWIRED=1
  CODEGRAPH_TELEMETRY=0 run codegraph uninstall --keep-cli --yes
}

codegraph_remove() { run npm uninstall -g @colbymchenry/codegraph; }

codegraph_status() {
  local a
  for a in claude vscode antigravity; do
    if mcp_has "$a" codegraph; then echo "    $a: wired"; else echo "    $a: -"; fi
  done
}

codegraph_project_ready() { [ -d .codegraph ]; }

codegraph_project_init() {
  if [ -d .codegraph ]; then say "  present    .codegraph/"; return 0; fi
  CODEGRAPH_TELEMETRY=0 run codegraph init
}
