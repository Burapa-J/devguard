#!/usr/bin/env bash
# agent-verify: run a command, keep its full output as evidence.
# Usage: agent-verify <name> -- <command> [args...]
# Writes .verify/<name>.log (override dir with VERIFY_DIR), prints one summary line,
# and exits with the command's exit code.
set -u

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<EOF
Usage: agent-verify <name> -- <command> [args...]

Runs <command>, writes full stdout/stderr and exit code to .verify/<name>.log
(override directory with VERIFY_DIR), and prints a one-line summary including
error line numbers (errors_at=L...) when errors or test failures are detected.
EOF
  exit 0
fi

if [ $# -lt 3 ] || [ "$2" != "--" ]; then
  echo "usage: agent-verify <name> -- <command> [args...]" >&2
  exit 64
fi

name=$1
shift 2

case "$name" in
  */* | .* | "") echo "agent-verify: invalid name '$name'" >&2; exit 64 ;;
esac

dir=${VERIFY_DIR:-.verify}
mkdir -p "$dir"
log="$dir/$name.log"

{
  echo "# cmd: $*"
  echo "# cwd: $PWD"
  echo "# started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$log"

"$@" >> "$log" 2>&1
code=$?

{
  echo "# finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# exit: $code"
} >> "$log"

lines=$(wc -l < "$log" | tr -d ' ')
err_lines=$(awk 'NR>3 && (/error:/ || /Fatal error:/ || /(^|[^A-Za-z])FAIL([^A-Za-z]|$)/ || /Test Case .* failed/ || /\*\* .* FAILED \*\*/) { printf "%sL%d", (c++ ? "," : ""), NR; if (c >= 10) exit }' "$log")
if [ -n "$err_lines" ]; then
  echo "agent-verify[$name] exit=$code lines=$lines errors_at=$err_lines log=$log"
else
  echo "agent-verify[$name] exit=$code lines=$lines log=$log"
fi
exit "$code"
