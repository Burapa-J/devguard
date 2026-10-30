# shellcheck shell=bash disable=SC2034,SC2016
# Component framework. Sourced after lib.sh.
#
# Each components/<name>.sh defines:
#   <name>_desc            one-line description
#   <name>_present         exit 0 if the tool's CLI is already on this machine
#   <name>_install         install the CLI (pinned version)
#   <name>_wire <agent>    connect it to one agent (claude | vscode | antigravity)
#   <name>_unwire <agent>  disconnect it from one agent
#   <name>_remove          uninstall the CLI (only called with --purge, and only if agent-kit installed it)
#   <name>_project_init    optional: per-repo setup, run by agent-kit-project
#
# State lives in ~/.agent-kit/components/<name>/: "wired" lists agents, "installed-by-kit" marks
# that agent-kit installed the CLI (so uninstall --purge never removes something you installed).

ALL_COMPONENTS="codegraph projectmem rtk context-mode"
DEFAULT_COMPONENTS="codegraph,projectmem,rtk"
STATE_DIR="$HOME/.agent-kit"

# MCP config files per agent. VS Code keeps user config under Application Support on macOS.
CLAUDE_MCP="$HOME/.claude.json"
AG_MCP="$HOME/.gemini/config/mcp_config.json"
OPENCODE_MCP="$HOME/.config/opencode/opencode.jsonc"
CURSOR_MCP="$HOME/.cursor/mcp.json"
CODEX_MCP="$HOME/.codex/config.toml"
GEMINI_MCP="$HOME/.gemini/settings.json"
if [ "$(uname -s)" = Darwin ]; then
  VSCODE_MCP="$HOME/Library/Application Support/Code/User/mcp.json"
else
  VSCODE_MCP="$HOME/.config/Code/User/mcp.json"
fi

# Function names cannot contain "-": context-mode -> context_mode.
fn_name() { printf '%s' "$1" | tr '-' '_'; }

need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  warn "$2"
  return 1
}

run() {
  local out rc
  if [ "$DRY_RUN" = 1 ]; then
    say "  would run: $*"
    return 0
  fi
  say "  run: $*"
  out=$(mktemp)
  "$@" > "$out" 2>&1
  rc=$?
  if [ "$rc" = 0 ]; then
    rm -f "$out"
    return 0
  fi
  cat "$out" >&2
  rm -f "$out"
  return "$rc"
}

state_dir() { printf '%s/components/%s' "$STATE_DIR" "$1"; }

state_mark_installed() {
  [ "$DRY_RUN" = 1 ] && return 0
  mkdir -p "$(state_dir "$1")"
  : > "$(state_dir "$1")/installed-by-kit"
}

state_add_wired() {
  local f
  [ "$DRY_RUN" = 1 ] && return 0
  mkdir -p "$(state_dir "$1")"
  f="$(state_dir "$1")/wired"
  grep -qxF "$2" "$f" 2>/dev/null || echo "$2" >> "$f"
}

state_wired() { cat "$(state_dir "$1")/wired" 2>/dev/null; }

state_installed_by_kit() { [ -f "$(state_dir "$1")/installed-by-kit" ]; }

state_forget() {
  [ "$DRY_RUN" = 1 ] && return 0
  rm -rf "$(state_dir "$1")"
  rmdir "$STATE_DIR/components" "$STATE_DIR" 2>/dev/null || true
}

agent_mcp_file() {
  case "$1" in
    claude) printf '%s' "$CLAUDE_MCP" ;;
    vscode) printf '%s' "$VSCODE_MCP" ;;
    antigravity) printf '%s' "$AG_MCP" ;;
    opencode) printf '%s' "$OPENCODE_MCP" ;;
    cursor) printf '%s' "$CURSOR_MCP" ;;
    codex) printf '%s' "$CODEX_MCP" ;;
    gemini) printf '%s' "$GEMINI_MCP" ;;
  esac
}

agent_mcp_key() { [ "$1" = vscode ] && printf servers || printf mcpServers; }

# mcp_set <agent> <name> <server-json>: add or replace one MCP server entry.
mcp_set() {
  local file key tmp cmd_str args_str
  file=$(agent_mcp_file "$1")
  key=$(agent_mcp_key "$1")
  if [ "$1" = codex ]; then
    # Codex uses TOML: [mcp_servers.<name>]
    if [ -f "$file" ] && grep -qxF "[mcp_servers.$2]" "$file" 2>/dev/null; then
      say "  unchanged  $file ($2)"
      return 0
    fi
    [ "$DRY_RUN" = 1 ] && { say "  would add MCP server '$2' to $file"; return 0; }
    backup "$file"
    mkdir -p "$(dirname "$file")"
    cmd_str=$(printf '%s' "$3" | jq -r '.command')
    args_str=$(printf '%s' "$3" | jq -c '.args // []')
    printf '\n[mcp_servers.%s]\ncommand = "%s"\nargs = %s\n' "$2" "$cmd_str" "$args_str" >> "$file"
    say "  updated    $file ($2)"
    return 0
  fi
  if [ "$1" = opencode ]; then
    need jq "jq is required to edit $file" || return 1
    if [ -f "$file" ] && jq -e --arg n "$2" '.mcp.servers[$n] != null or .mcp[$n] != null' "$file" >/dev/null 2>&1; then
      say "  unchanged  $file ($2)"
      return 0
    fi
    [ "$DRY_RUN" = 1 ] && { say "  would add MCP server '$2' to $file"; return 0; }
    tmp=$(mktemp)
    local oc_entry
    oc_entry=$(printf '%s' "$3" | jq '{type:"local", command: ([.command] + (.args // [])), disabled:false}')
    if [ -f "$file" ]; then
      jq --arg n "$2" --argjson v "$oc_entry" '.mcp.servers[$n] = $v' "$file" > "$tmp" ||
        { warn "$file is not valid JSON; '$2' not added"; rm -f "$tmp"; return 1; }
      backup "$file"
    else
      jq -n --arg n "$2" --argjson v "$oc_entry" '{mcp: {servers: {($n): $v}}}' > "$tmp"
      mkdir -p "$(dirname "$file")"
    fi
    cat "$tmp" > "$file"
    rm -f "$tmp"
    say "  updated    $file ($2)"
    return 0
  fi
  need jq "jq is required to edit $file" || return 1
  if [ -f "$file" ] && jq -e --arg k "$key" --arg n "$2" --argjson v "$3" \
       '.[$k][$n] == $v' "$file" >/dev/null 2>&1; then
    say "  unchanged  $file ($2)"
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    say "  would add MCP server '$2' to $file"
    return 0
  fi
  tmp=$(mktemp)
  if [ -f "$file" ]; then
    jq --arg k "$key" --arg n "$2" --argjson v "$3" '.[$k][$n] = $v' "$file" > "$tmp" ||
      { warn "$file is not valid JSON; '$2' not added"; rm -f "$tmp"; return 1; }
    backup "$file"
  else
    jq -n --arg k "$key" --arg n "$2" --argjson v "$3" '{($k): {($n): $v}}' > "$tmp"
    mkdir -p "$(dirname "$file")"
  fi
  cat "$tmp" > "$file"
  rm -f "$tmp"
  say "  updated    $file ($2)"
}

# mcp_del <agent> <name>: remove one MCP server entry; drop the file if nothing else is left in it.
mcp_del() {
  local file key tmp
  file=$(agent_mcp_file "$1")
  key=$(agent_mcp_key "$1")
  [ -f "$file" ] || return 0
  if [ "$1" = codex ]; then
    grep -qxF "[mcp_servers.$2]" "$file" 2>/dev/null || return 0
    [ "$DRY_RUN" = 1 ] && { say "  would remove MCP server '$2' from $file"; return 0; }
    backup "$file"
    tmp=$(mktemp)
    awk -v s="[mcp_servers.$2]" '$0==s{skip=1;next} /^\[/{skip=0} !skip' "$file" > "$tmp"
    if [ -z "$(tr -d '[:space:]' < "$tmp")" ]; then
      rm -f "$file"
      say "  removed    $file (only contained '$2')"
    else
      cat "$tmp" > "$file"
      say "  updated    $file (removed $2)"
    fi
    rm -f "$tmp"
    return 0
  fi
  if [ "$1" = opencode ]; then
    command -v jq >/dev/null 2>&1 || return 0
    jq -e --arg n "$2" '(.mcp.servers // {}) | has($n)' "$file" >/dev/null 2>&1 || return 0
    [ "$DRY_RUN" = 1 ] && { say "  would remove MCP server '$2' from $file"; return 0; }
    backup "$file"
    tmp=$(mktemp)
    jq --arg n "$2" 'del(.mcp.servers[$n]) | if .mcp.servers == {} then del(.mcp.servers) else . end | if .mcp == {} then del(.mcp) else . end' "$file" > "$tmp"
    if [ "$(jq -c . "$tmp")" = "{}" ]; then
      rm -f "$file"
      say "  removed    $file (only contained '$2')"
    else
      cat "$tmp" > "$file"
      say "  updated    $file (removed $2)"
    fi
    rm -f "$tmp"
    return 0
  fi
  command -v jq >/dev/null 2>&1 || { warn "jq missing; remove '$2' from $file by hand"; return 0; }
  jq -e --arg k "$key" --arg n "$2" '.[$k] | has($n)' "$file" >/dev/null 2>&1 || return 0
  if [ "$DRY_RUN" = 1 ]; then
    say "  would remove MCP server '$2' from $file"
    return 0
  fi
  backup "$file"
  tmp=$(mktemp)
  jq --arg k "$key" --arg n "$2" 'del(.[$k][$n]) | if .[$k] == {} then del(.[$k]) else . end' "$file" > "$tmp"
  if [ "$(jq -c . "$tmp")" = "{}" ]; then
    rm -f "$file"
    say "  removed    $file (only contained '$2')"
  else
    cat "$tmp" > "$file"
    say "  updated    $file (removed $2)"
  fi
  rm -f "$tmp"
}

mcp_has() {
  local file key
  file=$(agent_mcp_file "$1")
  key=$(agent_mcp_key "$1")
  if [ "$1" = codex ]; then
    [ -f "$file" ] && grep -qxF "[mcp_servers.$2]" "$file" 2>/dev/null
    return $?
  fi
  if [ "$1" = opencode ]; then
    [ -f "$file" ] && jq -e --arg n "$2" '((.mcp.servers // {}) | has($n)) or ((.mcp // {}) | has($n))' "$file" >/dev/null 2>&1
    return $?
  fi
  if [ -f "$file" ] && jq -e --arg k "$key" --arg n "$2" '.[$k] | has($n)' "$file" >/dev/null 2>&1; then
    return 0
  fi
  if [ "$1" = antigravity ] && [ -f "$HOME/.gemini/antigravity/mcp_config.json" ]; then
    jq -e --arg k "$key" --arg n "$2" '.[$k] | has($n)' "$HOME/.gemini/antigravity/mcp_config.json" >/dev/null 2>&1
    return $?
  fi
  return 1
}

load_components() {
  local c
  for c in $ALL_COMPONENTS; do
    # shellcheck source=/dev/null
    . "$KIT_DIR/components/$c.sh"
  done
}

valid_component() { case " $ALL_COMPONENTS " in *" $1 "*) return 0 ;; esac; return 1; }

# component_up <name> <agents...>: install if missing, then wire each agent.
component_up() {
  local c=$1 f a
  shift
  f=$(fn_name "$c")
  say "Component: $c — $("${f}_desc")"
  if "${f}_present"; then
    say "  present    $c CLI already installed"
  else
    "${f}_install" || { warn "$c install failed; not wired"; return 1; }
    state_mark_installed "$c"
  fi
  for a in "$@"; do
    "${f}_wire" "$a" && state_add_wired "$c" "$a"
  done
}

# component_upgrade <name>: if installed version differs from pinned version, re-run <name>_install.
component_upgrade() {
  local c=$1 f pinned inst
  f=$(fn_name "$c")
  "${f}_present" || return 0
  if type "${f}_pinned_version" >/dev/null 2>&1 && type "${f}_installed_version" >/dev/null 2>&1; then
    pinned=$("${f}_pinned_version")
    inst=$("${f}_installed_version")
    if [ -n "$pinned" ] && [ -n "$inst" ] && [ "$inst" != "$pinned" ]; then
      say "Component: $c — upgrading $inst -> $pinned"
      "${f}_install"
    fi
  fi
}

# component_down <name> <purge>: unwire every agent agent-kit wired; remove CLI on purge.
component_down() {
  local c=$1 purge=$2 f a
  f=$(fn_name "$c")
  say "Component: $c"
  for a in $(state_wired "$c"); do
    "${f}_unwire" "$a"
  done
  if state_installed_by_kit "$c"; then
    if [ "$purge" = 1 ]; then
      "${f}_remove"
      state_forget "$c"
    else
      # Keep the ownership marker so a later `uninstall --purge` can still remove the CLI.
      [ "$DRY_RUN" = 1 ] || rm -f "$(state_dir "$c")/wired"
      say "  kept       $c CLI (installed by agent-kit; remove with ./uninstall.sh --purge)"
    fi
  else
    [ "$purge" = 1 ] && say "  kept       $c CLI (not installed by agent-kit)"
    state_forget "$c"
  fi
}
