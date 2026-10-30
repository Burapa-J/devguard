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
# Hook commands are run by a shell, so paths are single-quoted (the kit path may contain spaces).
# Single quotes, not backslashes: JSON stores them unescaped, so the command can be matched as text.
shell_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
HOOK_CMD=$(shell_quote "$KIT_DIR/hooks/remind.sh")
VERIFY_LINK="$HOME/.local/bin/agent-verify"
PROJECT_LINK="$HOME/.local/bin/devguard-project"
CLI_LINK="$HOME/.local/bin/devguard"
LEGACY_LINKS="$HOME/.local/bin/potless $HOME/.local/bin/agent-kit $HOME/.local/bin/agent-kit-project"
AUTO_HOOK_CMD="$(shell_quote "$KIT_DIR/bin/project.sh") auto"
AUTO_ROOTS="$HOME/.agent-kit/auto-roots"

# Rules files and skill directories per target.
CLAUDE_RULES="$HOME/.claude/CLAUDE.md"
CLAUDE_SKILLS="$HOME/.claude/skills"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
VSCODE_RULES="$HOME/.copilot/copilot-instructions.md"
VSCODE_SKILLS="$HOME/.copilot/skills"
AG_RULES="$HOME/.gemini/GEMINI.md"
AG_SKILLS="$HOME/.gemini/config/skills"
AG_CLI_SKILLS="$HOME/.gemini/antigravity-cli/skills"
OPENCODE_RULES="$HOME/.config/opencode/AGENTS.md"
OPENCODE_SKILLS="$HOME/.config/opencode/skills"
CURSOR_RULES="$HOME/.cursor/rules/devguard.mdc"
LEGACY_CURSOR_RULES="$HOME/.cursor/rules/potless.mdc $HOME/.cursor/rules/agent-kit.mdc"
CURSOR_SKILLS="$HOME/.cursor/skills"
CODEX_RULES="$HOME/.codex/AGENTS.md"
CODEX_SKILLS="$HOME/.codex/skills"
GEMINI_SKILLS="$HOME/.gemini/skills"

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

# Keep at most the 10 newest backup snapshots under ~/.agent-kit-backup.
prune_backups() {
  local root="$HOME/.agent-kit-backup" count=0 d
  [ -d "$root" ] || return 0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    count=$((count + 1))
    if [ "$count" -gt 10 ]; then rm -rf "$d"; fi
  done <<EOF
$(ls -1dt "$root"/* 2>/dev/null || true)
EOF
  return 0
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
# edit_settings <filter> [command] [matcher]: the filter sees them as $cmd and $matcher.
edit_settings() {
  local filter=$1 cmd=${2:-$HOOK_CMD} matcher=${3:-compact} file=$CLAUDE_SETTINGS tmp src
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq not found; skipping Claude Code hook. See README for the manual snippet."
    return 0
  fi
  src=$file
  [ -f "$file" ] || src=/dev/null
  tmp=$(mktemp)
  if [ "$src" = /dev/null ]; then
    echo '{}' | jq --arg cmd "$cmd" --arg matcher "$matcher" "$filter" > "$tmp"
  elif ! jq --arg cmd "$cmd" --arg matcher "$matcher" "$filter" "$src" > "$tmp"; then
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

# Leaves the file alone when the hook is already there with the same matcher: removing and
# re-appending would reorder it behind our other SessionStart hook and rewrite settings.json on
# every install.
JQ_ADD_HOOK='
  if any(.hooks.SessionStart[]?; .matcher == $matcher
         and ((.hooks | type) == "array") and any(.hooks[]; .command == $cmd)) then .
  else '"$JQ_REMOVE_HOOK"'
    | .hooks.SessionStart = ((.hooks.SessionStart // [])
        + [{"matcher": $matcher, "hooks": [{"type": "command", "command": $cmd}]}])
  end'

# ---- automatic project setup: zsh hook and launchd agent ---------------------------------------

ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
ZSH_BEGIN="# >>> agent-kit >>>"
ZSH_END="# <<< agent-kit <<<"
LAUNCHD_LABEL="com.agent-kit.scan"
LAUNCHD_DIR="${AGENT_KIT_LAUNCHD_DIR:-$HOME/Library/LaunchAgents}"
LAUNCHD_PLIST="$LAUNCHD_DIR/$LAUNCHD_LABEL.plist"

# macOS only; AGENT_KIT_FORCE_LAUNCHD=1 lets tests write the plist on Linux.
use_launchd() { [ "$(uname -s)" = Darwin ] || [ "${AGENT_KIT_FORCE_LAUNCHD:-0}" = 1 ]; }

zsh_block_body() {
  cat <<ZSH
# Sets up git repositories under the folders in ~/.agent-kit/auto-roots when you cd into them.
agent_kit_chpwd() { $(shell_quote "$KIT_DIR/bin/project.sh") auto >/dev/null 2>&1 &! }
autoload -Uz add-zsh-hook && add-zsh-hook chpwd agent_kit_chpwd
ZSH
}

zsh_strip() { awk -v b="$ZSH_BEGIN" -v e="$ZSH_END" '$0==b{s=1;next} $0==e{s=0;next} !s' "$1"; }

zsh_hook_set() {
  local rest="" tmp
  [ -f "$ZSHRC" ] && rest=$(zsh_strip "$ZSHRC")
  tmp=$(mktemp)
  if [ -n "$rest" ]; then
    printf '%s\n\n%s\n%s\n%s\n' "$rest" "$ZSH_BEGIN" "$(zsh_block_body)" "$ZSH_END" > "$tmp"
  else
    printf '%s\n%s\n%s\n' "$ZSH_BEGIN" "$(zsh_block_body)" "$ZSH_END" > "$tmp"
  fi
  if [ -f "$ZSHRC" ] && cmp -s "$tmp" "$ZSHRC"; then
    say "  unchanged  $ZSHRC"
  elif [ "$DRY_RUN" = 1 ]; then
    say "  would add cd hook to $ZSHRC"
  else
    backup "$ZSHRC"
    cat "$tmp" > "$ZSHRC"
    say "  updated    $ZSHRC (cd hook)"
  fi
  rm -f "$tmp"
}

zsh_hook_remove() {
  local rest
  [ -f "$ZSHRC" ] && grep -qxF "$ZSH_BEGIN" "$ZSHRC" || return 0
  rest=$(zsh_strip "$ZSHRC")
  if [ "$DRY_RUN" = 1 ]; then say "  would remove cd hook from $ZSHRC"; return 0; fi
  backup "$ZSHRC"
  if [ -z "$rest" ]; then rm -f "$ZSHRC"; else printf '%s\n' "$rest" > "$ZSHRC"; fi
  say "  cleaned    $ZSHRC"
}

launchd_plist_body() {
  local xml_kit
  xml_kit=$(printf '%s' "$KIT_DIR/bin/project.sh" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LAUNCHD_LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$xml_kit</string><string>scan</string></array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
  <key>StartInterval</key><integer>1800</integer>
  <key>RunAtLoad</key><true/>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>10</integer>
  <key>StandardOutPath</key><string>$HOME/.agent-kit/logs/scan.log</string>
  <key>StandardErrorPath</key><string>$HOME/.agent-kit/logs/scan.log</string>
</dict>
</plist>
PLIST
}

launchd_set() {
  local tmp
  use_launchd || { say "  skipped    periodic scan (launchd is macOS only)"; return 0; }
  tmp=$(mktemp)
  launchd_plist_body > "$tmp"
  if [ -f "$LAUNCHD_PLIST" ] && cmp -s "$tmp" "$LAUNCHD_PLIST"; then
    say "  unchanged  $LAUNCHD_PLIST"
  elif [ "$DRY_RUN" = 1 ]; then
    say "  would install periodic scan $LAUNCHD_PLIST (every 30 min)"
  else
    mkdir -p "$LAUNCHD_DIR" "$HOME/.agent-kit/logs"
    cat "$tmp" > "$LAUNCHD_PLIST"
    if command -v launchctl >/dev/null 2>&1; then
      launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" >/dev/null 2>&1 || true
      launchctl bootstrap "gui/$(id -u)" "$LAUNCHD_PLIST" || warn "launchctl could not load $LAUNCHD_PLIST"
    fi
    say "  installed  $LAUNCHD_PLIST (every 30 min)"
  fi
  rm -f "$tmp"
}

launchd_remove() {
  [ -f "$LAUNCHD_PLIST" ] || return 0
  if [ "$DRY_RUN" = 1 ]; then say "  would remove $LAUNCHD_PLIST"; return 0; fi
  if command -v launchctl >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" >/dev/null 2>&1 || true
  fi
  rm -f "$LAUNCHD_PLIST"
  say "  removed    $LAUNCHD_PLIST"
}
