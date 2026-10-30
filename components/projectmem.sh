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

projectmem_pinned_version() { echo "$PROJECTMEM_VERSION"; }

projectmem_installed_version() {
  "$PROJECTMEM_VENV/bin/python" -c 'import importlib.metadata as m; print(m.version("projectmem"))' 2>/dev/null | tr -d '[:space:]'
}

projectmem_install() {
  local b
  need python3 "python3 not found; install it first (xcode-select --install or brew install python)" || return 1
  run python3 -m venv "$PROJECTMEM_VENV" || return 1
  run "$PROJECTMEM_VENV/bin/pip" install --quiet "projectmem==$PROJECTMEM_VERSION" || return 1
  for b in $PROJECTMEM_LINKS; do
    link "$HOME/.local/bin/$b" "$PROJECTMEM_VENV/bin/$b"
  done
  [ -n "${STUB_LOG:-}" ] || [ "$DRY_RUN" = 1 ] || "$PROJECTMEM_VENV/bin/python" "$KIT_DIR/bin/pjm_sync.py" install-hook >/dev/null 2>&1 || true
}

projectmem_server() {
  printf '{"command":"%s","args":["-m","projectmem.mcp_server"]}' "$PROJECTMEM_VENV/bin/python"
}

projectmem_wire() {
  [ -n "${STUB_LOG:-}" ] || [ "$DRY_RUN" = 1 ] || [ ! -x "$PROJECTMEM_VENV/bin/python" ] ||
    "$PROJECTMEM_VENV/bin/python" "$KIT_DIR/bin/pjm_sync.py" install-hook >/dev/null 2>&1 || true
  mcp_set "$1" projectmem "$(projectmem_server)"
}

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

projectmem_project_ready() {
  [ -d .projectmem ] || return 1
  [ -n "${STUB_LOG:-}" ] && return 0
  [ -f .projectmem/config.toml ] || return 1
  [ -f .git/hooks/post-commit ] && grep -q "pjm\|projectmem" .git/hooks/post-commit 2>/dev/null || return 1
  [ -f "$HOME/.projectmem/projects.json" ] && grep -qF "\"$PWD\"" "$HOME/.projectmem/projects.json" 2>/dev/null || return 1
  return 0
}

projectmem_project_init() {
  if projectmem_project_ready; then say "  present    .projectmem/"; return 0; fi
  # pjm init also installs git hooks and creates/updates CLAUDE.md and AGENTS.md with a
  # "projectmem bridge" section. Undo per repo with: pjm hooks uninstall, and delete .projectmem/.
  run "$PROJECTMEM_VENV/bin/pjm" init
  [ -n "${STUB_LOG:-}" ] || [ "$DRY_RUN" = 1 ] || "$PROJECTMEM_VENV/bin/python" "$KIT_DIR/bin/pjm_sync.py" --quiet "$PWD" >/dev/null 2>&1 || true
}
