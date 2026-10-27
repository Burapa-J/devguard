#!/usr/bin/env bash
# agent-kit-project: per-repository setup for the components agent-kit manages.
# Usage: agent-kit-project init [--dry-run]   (run inside a git repository)
set -eu

SELF=$0
while [ -L "$SELF" ]; do
  link_target=$(readlink "$SELF")
  case "$link_target" in /*) SELF=$link_target ;; *) SELF="$(dirname "$SELF")/$link_target" ;; esac
done
KIT_DIR=$(cd "$(dirname "$SELF")/.." && pwd -P)

cmd=${1:-}
DRY_RUN=0
[ "${2:-}" = --dry-run ] && DRY_RUN=1
# shellcheck disable=SC2034  # read by lib.sh
BACKUP_DIR=""

if [ "$cmd" != init ]; then
  echo "usage: agent-kit-project init [--dry-run]" >&2
  exit 64
fi

# shellcheck source=lib.sh
. "$KIT_DIR/lib.sh"
# shellcheck source=components/common.sh
. "$KIT_DIR/components/common.sh"
load_components

git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "agent-kit-project: not inside a git repository" >&2; exit 1; }
cd "$(git rev-parse --show-toplevel)"
say "Project: $PWD"

if [ -f .gitignore ] && grep -qxF '.verify/' .gitignore; then
  say "  present    .verify/ in .gitignore"
elif [ "$DRY_RUN" = 1 ]; then
  say "  would add .verify/ to .gitignore"
else
  if [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ]; then echo >> .gitignore; fi
  echo '.verify/' >> .gitignore
  say "  updated    .gitignore (.verify/)"
fi

for c in $ALL_COMPONENTS; do
  f=$(fn_name "$c")
  [ -d "$(state_dir "$c")" ] || continue
  type "${f}_project_init" >/dev/null 2>&1 || continue
  say "Component: $c"
  "${f}_project_init"
done
say "Done."
