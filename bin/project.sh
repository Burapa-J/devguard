#!/usr/bin/env bash
# agent-kit-project: per-repository setup for the components agent-kit manages.
#
#   agent-kit-project init [--dry-run]      set up the git repository you are in
#   agent-kit-project init-all <dir> [--dry-run]
#                                           set up every git repository under <dir> (2 levels deep)
#   agent-kit-project auto                  used by the Claude Code hook and the zsh hook: if this repo
#                                           is under a root listed in ~/.agent-kit/auto-roots and is
#                                           not set up yet, set it up in the background
#   agent-kit-project scan                  used by launchd: set up every repo under the auto roots
#                                           that is not set up yet (covers VS Code and Antigravity)
#
# A repository containing a file named .agent-kit-skip is never set up automatically.
set -eu

SELF=$0
while [ -L "$SELF" ]; do
  link_target=$(readlink "$SELF")
  case "$link_target" in /*) SELF=$link_target ;; *) SELF="$(dirname "$SELF")/$link_target" ;; esac
done
KIT_DIR=$(cd "$(dirname "$SELF")/.." && pwd -P)
SELF="$KIT_DIR/bin/project.sh"

cmd=${1:-}
DRY_RUN=0
for a in "$@"; do [ "$a" = --dry-run ] && DRY_RUN=1; done
# shellcheck disable=SC2034  # read by lib.sh
BACKUP_DIR=""

usage() {
  echo "usage: agent-kit-project init [--dry-run] | init-all <dir> [--dry-run] | auto | scan" >&2
  exit 64
}

if [ "$cmd" = "-h" ] || [ "$cmd" = "--help" ] || [ "$cmd" = "help" ]; then
  cat <<EOF
Usage: agent-kit-project <subcommand> [options]

  init [--dry-run]            Set up the current git repository (.gitignore, codegraph, projectmem)
  init-all <dir> [--dry-run]  Set up every git repository under <dir> (1-2 levels deep)
  auto                        Background setup for current repo if under ~/.agent-kit/auto-roots
  scan                        Periodic scan of all repos under ~/.agent-kit/auto-roots
EOF
  exit 0
fi

# shellcheck source=lib.sh
. "$KIT_DIR/lib.sh"
# shellcheck source=components/common.sh
. "$KIT_DIR/components/common.sh"
load_components

# Components that are currently wired by agent-kit and have per-project setup.
project_components() {
  local c f
  for c in $ALL_COMPONENTS; do
    f=$(fn_name "$c")
    [ -n "$(state_wired "$c")" ] || continue
    type "${f}_project_init" >/dev/null 2>&1 || continue
    echo "$c"
  done
}

gitignore_ready() { [ -f .gitignore ] && grep -qxF '.verify/' .gitignore; }

# Exit 0 when the repository in $PWD needs nothing.
project_ready() {
  local c
  gitignore_ready || return 1
  for c in $(project_components); do
    "$(fn_name "$c")_project_ready" || return 1
  done
}

init_here() {
  local c
  say "Project: $PWD"
  if gitignore_ready; then
    say "  present    .verify/ in .gitignore"
  elif [ "$DRY_RUN" = 1 ]; then
    say "  would add .verify/ to .gitignore"
  else
    if [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ]; then echo >> .gitignore; fi
    echo '.verify/' >> .gitignore
    say "  updated    .gitignore (.verify/)"
  fi
  for c in $(project_components); do
    say "Component: $c"
    "$(fn_name "$c")_project_init"
  done
}

under_auto_root() {
  local root
  [ -f "$AUTO_ROOTS" ] || return 1
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    case "$1/" in "${root%/}"/*) return 0 ;; esac
  done < "$AUTO_ROOTS"
  return 1
}

# Repositories at <dir>/<repo> and <dir>/<group>/<repo>; .git may be a dir or a worktree file.
list_repos() {
  find "$1" -mindepth 2 -maxdepth 3 -name .git -not -path '*/node_modules/*' 2>/dev/null |
    while IFS= read -r g; do dirname "$g"; done | LC_ALL=C sort
}

lock_path() { printf '%s/locks/%s' "$STATE_DIR" "$(printf '%s' "$1" | cksum | cut -d' ' -f1)"; }

case "$cmd" in
  init)
    top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "agent-kit-project: not inside a git repository" >&2; exit 1; }
    cd "$top"
    init_here
    say "Done."
    ;;

  init-all)
    [ -n "${2:-}" ] && [ -d "$2" ] || usage
    count=0
    skipped=0
    list_repos "$2" > "${TMPDIR:-/tmp}/agent-kit-repos.$$"
    while IFS= read -r repo; do
      if [ -e "$repo/.agent-kit-skip" ]; then
        say "Project: $repo"; say "  skipped    .agent-kit-skip"; skipped=$((skipped + 1)); continue
      fi
      ( cd "$repo" && init_here < /dev/null ) || warn "setup failed in $repo"
      count=$((count + 1))
    done < "${TMPDIR:-/tmp}/agent-kit-repos.$$"
    rm -f "${TMPDIR:-/tmp}/agent-kit-repos.$$"
    say "Done: $count repositories ($skipped skipped)."
    ;;

  scan)
    # Periodic and quiet: only repos that still need setup are touched and logged.
    [ -f "$AUTO_ROOTS" ] || exit 0
    mkdir -p "$STATE_DIR/locks"
    while IFS= read -r root; do
      [ -d "$root" ] || continue
      list_repos "$root" > "${TMPDIR:-/tmp}/agent-kit-scan.$$"
      while IFS= read -r repo; do
        [ -e "$repo/.agent-kit-skip" ] && continue
        ( cd "$repo" && project_ready ) && continue
        lock=$(lock_path "$repo")
        mkdir "$lock" 2>/dev/null || continue
        echo "$(date '+%Y-%m-%d %H:%M:%S') setting up $repo"
        ( cd "$repo" && init_here < /dev/null ) || warn "setup failed in $repo"
        rmdir "$lock"
      done < "${TMPDIR:-/tmp}/agent-kit-scan.$$"
      rm -f "${TMPDIR:-/tmp}/agent-kit-scan.$$"
    done < "$AUTO_ROOTS"
    ;;

  auto)
    # Runs on every Claude Code session start, so it must be fast and quiet. Anything printed
    # here is added to the agent's context.
    dir=${CLAUDE_PROJECT_DIR:-$PWD}
    top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
    under_auto_root "$top" || exit 0
    [ -e "$top/.agent-kit-skip" ] && exit 0
    cd "$top"
    project_ready && exit 0
    mkdir -p "$STATE_DIR/logs" "$STATE_DIR/locks"
    lock=$(lock_path "$top")
    mkdir "$lock" 2>/dev/null || exit 0
    log="$STATE_DIR/logs/$(basename "$top").log"
    # shellcheck disable=SC2016  # positional args expand inside the child shell
    nohup /bin/sh -c '"$1" init > "$2" 2>&1; rmdir "$3"' sh "$SELF" "$log" "$lock" \
      < /dev/null > /dev/null 2>&1 &
    echo "[agent-kit] Setting up this repository in the background (code index, project memory). Log: $log"
    ;;

  *) usage ;;
esac
