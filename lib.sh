# shellcheck shell=bash disable=SC2034,SC2016
# SC2034: variables are used by the scripts that source this file.
# SC2016: $cmd inside jq filters is a jq variable, not a shell one.
# Shared helpers for install.sh / uninstall.sh.
# Written for bash 3.2 (macOS /bin/bash): no associative arrays, no mapfile, no ${var,,}.

BEGIN_MARK="<!-- agent-kit:begin -->"
END_MARK="<!-- agent-kit:end -->"
DRY_RUN=${DRY_RUN:-0}
BACKUP_DIR=${BACKUP_DIR:-}

SKILL_NAME="verified-dev"
HOOK_CMD="$KIT_DIR/hooks/remind.sh"
VERIFY_LINK="$HOME/.local/bin/agent-verify"

# Rules files and skill directories per target.
CLAUDE_RULES="$HOME/.claude/CLAUDE.md"
CLAUDE_SKILLS="$HOME/.claude/skills"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
VSCODE_RULES="$HOME/.copilot/copilot-instructions.md"
VSCODE_SKILLS="$HOME/.copilot/skills"
AG_RULES="$HOME/.gemini/GEMINI.md"
AG_SKILLS="$HOME/.gemini/config/skills"
AG_CLI_SKILLS="$HOME/.gemini/antigravity-cli/skills"

say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

# Copy a file into BACKUP_DIR (once per run) before it is changed.
backup() {
  local f=$1 rel dest
  [ -n "$BACKUP_DIR" ] || return 0
  [ -e "$f" ] || [ -L "$f" ] || return 0
  rel=${f#"$HOME"/}
  dest="$BACKUP_DIR/$rel"
  if [ -e "$dest" ] || [ -L "$dest" ]; then return 0; fi
  mkdir -p "$(dirname "$dest")"
  cp -RP "$f" "$dest"
}

# Print a file without the agent-kit block. Callers use $(...) so trailing blank lines are dropped.
strip_block() {
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '$0==b{s=1;next} $0==e{s=0;next} !s' "$1"
}

has_block() {
  [ -f "$1" ] && grep -qxF "$BEGIN_MARK" "$1"
}

# Write $2's content into $1 between the markers, replacing any previous block.
set_block() {
  local file=$1 body=$2 rest="" tmp
  [ -f "$file" ] && rest=$(strip_block "$file")
  tmp=$(mktemp)
  if [ -n "$rest" ]; then
    printf '%s\n\n%s\n%s\n%s\n' "$rest" "$BEGIN_MARK" "$(cat "$body")" "$END_MARK" > "$tmp"
  else
    printf '%s\n%s\n%s\n' "$BEGIN_MARK" "$(cat "$body")" "$END_MARK" > "$tmp"
  fi
  if [ -f "$file" ] && cmp -s "$tmp" "$file"; then
    say "  unchanged  $file"
  elif [ "$DRY_RUN" = 1 ]; then
    say "  would update rules block in $file"
  else
    backup "$file"
    mkdir -p "$(dirname "$file")"
    cat "$tmp" > "$file"
    say "  updated    $file"
  fi
  rm -f "$tmp"
}

remove_block() {
  local file=$1 rest
  has_block "$file" || return 0
  rest=$(strip_block "$file")
  if [ "$DRY_RUN" = 1 ]; then
    say "  would remove rules block from $file"
    return 0
  fi
  backup "$file"
  if [ -z "$rest" ]; then
    rm -f "$file"
    say "  removed    $file (only contained agent-kit block)"
  else
    printf '%s\n' "$rest" > "$file"
    say "  cleaned    $file"
  fi
}

is_ours() {
  local cur
  [ -L "$1" ] || return 1
  cur=$(readlink "$1")
  case "$cur" in "$KIT_DIR"/*) return 0 ;; esac
  return 1
}

# Symlink $1 -> $2. Never replaces a real file or someone else's symlink.
link() {
  local target=$1 src=$2
  if [ -L "$target" ] && [ "$(readlink "$target")" = "$src" ]; then
    say "  unchanged  $target"
    return 0
  fi
  if [ -L "$target" ] && ! is_ours "$target"; then
    warn "$target is a symlink to $(readlink "$target"); skipped"
    return 0
  fi
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    warn "$target already exists and is not managed by agent-kit; skipped"
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    say "  would link $target -> $src"
    return 0
  fi
  mkdir -p "$(dirname "$target")"
  ln -sfn "$src" "$target"
  say "  linked     $target -> $src"
}

unlink_ours() {
  is_ours "$1" || return 0
  if [ "$DRY_RUN" = 1 ]; then
    say "  would remove link $1"
  else
    rm -f "$1"
    say "  unlinked   $1"
  fi
}

# Apply a jq filter to Claude Code settings.json in place (with backup).
edit_settings() {
  local filter=$1 file=$CLAUDE_SETTINGS tmp src
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq not found; skipping Claude Code hook. See README for the manual snippet."
    return 0
  fi
  src=$file
  [ -f "$file" ] || src=/dev/null
  tmp=$(mktemp)
  if [ "$src" = /dev/null ]; then
    echo '{}' | jq --arg cmd "$HOOK_CMD" "$filter" > "$tmp"
  elif ! jq --arg cmd "$HOOK_CMD" "$filter" "$src" > "$tmp"; then
    warn "$file is not valid JSON; hook not changed"
    rm -f "$tmp"
    return 0
  fi
  if [ -f "$file" ] && jq -e --slurpfile a "$tmp" '. == $a[0]' "$file" >/dev/null 2>&1; then
    say "  unchanged  $file"
  elif [ "$(jq -c . "$tmp")" = "{}" ] && [ ! -f "$file" ]; then
    : # nothing to write
  elif [ "$DRY_RUN" = 1 ]; then
    say "  would update hooks in $file"
  elif [ "$(jq -c . "$tmp")" = "{}" ]; then
    backup "$file"
    rm -f "$file"
    say "  removed    $file (only contained agent-kit hook)"
  else
    backup "$file"
    mkdir -p "$(dirname "$file")"
    cat "$tmp" > "$file"
    say "  updated    $file"
  fi
  rm -f "$tmp"
}

JQ_REMOVE_HOOK='
  if (.hooks.SessionStart | type) == "array" then
    .hooks.SessionStart |= (map(if (.hooks | type) == "array"
                                then .hooks |= map(select(.command != $cmd)) else . end)
                            | map(select((.hooks | type) != "array" or (.hooks | length) > 0)))
  else . end
  | if .hooks.SessionStart == [] then del(.hooks.SessionStart) else . end
  | if .hooks == {} then del(.hooks) else . end'

JQ_ADD_HOOK="$JQ_REMOVE_HOOK"'
  | .hooks.SessionStart = ((.hooks.SessionStart // [])
      + [{"matcher": "compact", "hooks": [{"type": "command", "command": $cmd}]}])'
