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

# ---- cross-machine sync health (bin/pjm_sync.py), shared by status.sh and doctor.sh ----------

projectmem_sync_hub() {
  printf '%s' "${DEVGUARD_SYNC_DIR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/devguard-sync}"
}

projectmem_sync_pth() {
  ls -d "$PROJECTMEM_VENV"/lib/python*/site-packages/devguard_pjm_sync.pth 2>/dev/null | head -n 1
}

# The .pth hook must load pjm_sync.py from this kit; a moved or re-cloned kit leaves it pointing at a
# path that no longer exists, and projectmem then runs without sync or the events lock.
projectmem_sync_hook_ok() {
  local pth
  pth=$(projectmem_sync_pth)
  [ -n "$pth" ] && grep -qF "'$KIT_DIR/bin'" "$pth" && [ -f "$KIT_DIR/bin/pjm_sync.py" ]
}

# Device ids that have written a node file to the hub, one per line.
projectmem_sync_devices() {
  local f
  for f in "$(projectmem_sync_hub)"/projects/*/nodes/*.jsonl; do
    [ -f "$f" ] && basename "$f" .jsonl
  done | LC_ALL=C sort -u
}

# PIDs of running projectmem MCP servers started before <file> last changed. Python loads
# pjm_sync.py once at startup, so these servers still run the old sync code until restarted.
projectmem_stale_mcp_pids() {
  local file=${1:-$KIT_DIR/bin/pjm_sync.py} mtime
  mtime=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null) || return 0
  ps -axo pid=,etime=,command= 2>/dev/null | awk -v now="$(date +%s)" -v mt="$mtime" '
    $3 ~ /[Pp]ython[0-9.]*$/ && $0 ~ / -m projectmem[.]mcp_server/ {
      n = split($2, t, /[-:]/); s = 0
      if ($2 ~ /-/) s = t[1] * 86400 + t[2] * 3600 + t[3] * 60 + t[4]
      else if (n == 3) s = t[1] * 3600 + t[2] * 60 + t[3]
      else s = t[1] * 60 + t[2]
      if (now - s < mt) print $1
    }'
}

projectmem_project_ready() {
  local hook
  [ -d .projectmem ] || return 1
  [ -n "${STUB_LOG:-}" ] && return 0
  [ -f .projectmem/config.toml ] || return 1
  # --git-path follows linked worktrees (.git is a file there) and core.hooksPath.
  hook=$(git rev-parse --git-path hooks/post-commit 2>/dev/null) || return 1
  [ -f "$hook" ] && grep -q "pjm\|projectmem" "$hook" 2>/dev/null || return 1
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
