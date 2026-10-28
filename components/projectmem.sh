# shellcheck shell=bash
# projectmem — per-project memory (issues, attempts, fixes, decisions) over MCP.
# Upstream: https://github.com/riponcm/projectmem  (PyPI: projectmem)
# Installed into its own venv so macOS's externally-managed Python is never touched.
# One global MCP server serves every project registered with `pjm init`.

PROJECTMEM_VERSION=0.3.4
PROJECTMEM_VENV="$HOME/.local/share/agent-kit/projectmem-venv"
PROJECTMEM_LINKS="pjm projectmem"

projectmem_desc() { echo "project memory via MCP (PyPI projectmem==$PROJECTMEM_VERSION)"; }

projectmem_present() { [ -x "$PROJECTMEM_VENV/bin/python" ] && [ -x "$PROJECTMEM_VENV/bin/pjm" ]; }

projectmem_install() {
  local b
  need python3 "python3 not found; install it first (xcode-select --install or brew install python)" || return 1
  run python3 -m venv "$PROJECTMEM_VENV" || return 1
  run "$PROJECTMEM_VENV/bin/pip" install --quiet "projectmem==$PROJECTMEM_VERSION" || return 1
  for b in $PROJECTMEM_LINKS; do
    link "$HOME/.local/bin/$b" "$PROJECTMEM_VENV/bin/$b"
  done
}

projectmem_server() {
  printf '{"command":"%s","args":["-m","projectmem.mcp_server"]}' "$PROJECTMEM_VENV/bin/python"
}

projectmem_wire() { mcp_set "$1" projectmem "$(projectmem_server)"; }

projectmem_unwire() { mcp_del "$1" projectmem; }

projectmem_remove() {
  local b
  for b in $PROJECTMEM_LINKS; do
    if [ -L "$HOME/.local/bin/$b" ]; then
      if [ "$DRY_RUN" = 1 ]; then say "  would remove link $HOME/.local/bin/$b"; else rm -f "$HOME/.local/bin/$b"; fi
    fi
  done
  if [ "$DRY_RUN" = 1 ]; then
    say "  would remove $PROJECTMEM_VENV"
  else
    rm -rf "$PROJECTMEM_VENV"
    rmdir "$HOME/.local/share/agent-kit" 2>/dev/null || true
    say "  removed    $PROJECTMEM_VENV"
  fi
}

projectmem_status() {
  local a
  for a in claude vscode antigravity; do
    if mcp_has "$a" projectmem; then echo "    $a: wired"; else echo "    $a: -"; fi
  done
}

projectmem_project_ready() { [ -d .projectmem ]; }

projectmem_project_init() {
  if [ -d .projectmem ]; then say "  present    .projectmem/"; return 0; fi
  # pjm init also installs git hooks and creates/updates CLAUDE.md and AGENTS.md with a
  # "projectmem bridge" section. Undo per repo with: pjm hooks uninstall, and delete .projectmem/.
  run "$PROJECTMEM_VENV/bin/pjm" init
}
