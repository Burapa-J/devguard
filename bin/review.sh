#!/usr/bin/env bash
# devguard review: have a model from another vendor review a change before you call it done.
#
#   devguard review [--with claude|gemini|agy] [--base REF]
#
# Reviews uncommitted changes, or the last commit when the tree is clean, or REF...HEAD plus any
# uncommitted changes with --base. The reviewer runs read-only (plan mode) inside the repo so it can
# open files for context. The report goes to .verify/review-<time>.md; one summary line is printed.
# Default reviewer: $DEVGUARD_REVIEWER, else the first installed of claude, agy, gemini (Gemini CLI
# is refused for individual accounts; agy reaches Gemini through Antigravity).
set -u

MAX_DIFF_BYTES=200000
with=${DEVGUARD_REVIEWER:-}
base=""

while [ $# -gt 0 ]; do
  case "$1" in
    --with) with=${2:-}; shift 2 ;;
    --with=*) with=${1#--with=}; shift ;;
    --base) base=${2:-}; shift 2 ;;
    --base=*) base=${1#--base=}; shift ;;
    -h | --help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "devguard review: unknown option $1" >&2; exit 64 ;;
  esac
done

if [ -z "$with" ]; then
  for c in claude agy gemini; do
    if command -v "$c" >/dev/null 2>&1; then with=$c; break; fi
  done
  [ -n "$with" ] || { echo "devguard review: no reviewer CLI found (claude, agy or gemini)" >&2; exit 69; }
fi
case "$with" in claude | gemini | agy) ;; *) echo "devguard review: unknown reviewer '$with' (claude, gemini, agy)" >&2; exit 64 ;; esac
command -v "$with" >/dev/null 2>&1 || { echo "devguard review: '$with' is not installed" >&2; exit 69; }

top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "devguard review: not inside a git repository" >&2; exit 64; }
cd "$top" || exit 64

if [ -n "$base" ]; then
  what="changes since $base"
  diff=$(git diff "$base...HEAD"; git diff HEAD)
elif [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  what="uncommitted changes"
  diff=$(git diff HEAD)
else
  what="last commit $(git rev-parse --short HEAD)"
  diff=$(git show --format='commit %H%n%n%B' HEAD)
fi
[ -n "$diff" ] || { echo "devguard review: nothing to review"; exit 0; }
if [ "${#diff}" -gt "$MAX_DIFF_BYTES" ]; then
  diff="${diff:0:$MAX_DIFF_BYTES}
[diff truncated at $MAX_DIFF_BYTES bytes; open the files for the rest]"
fi

prompt="You are reviewing a code change written by another AI model. Your job is to find defects
before they ship, not to praise or restyle. The change ($what) is below. Open any repository file
you need for context, but do not modify anything.

Report only problems you can defend, most severe first, one per line:
- [BLOCKER|MAJOR|MINOR] file:line - the problem - a concrete input or state that breaks it - the fix

Look for:
1. Correctness bugs: wrong results, crashes, swallowed errors, edge cases.
2. Failure modes: concurrent or multi-device use, partial failure and rerun, upgrade or rollback,
   data loss, security (secrets, injection, unsafe deletes).
3. Tests: missing tests for the change, and tests that would still pass without the change.
4. Claims in comments, docs or commit messages that the code does not back up.

End each finding with its source: (read file:line) if you opened the code, (inferred) otherwise.
If nothing survives scrutiny, say so plainly. Finish with exactly one line:
VERDICT: SHIP   or   VERDICT: CHANGES NEEDED

--- CHANGE ---
$diff"

case "$with" in
  claude) cmd=(claude -p "$prompt" --permission-mode plan) ;;
  gemini) cmd=(gemini -p "$prompt" --approval-mode plan) ;;
  agy) cmd=(agy -p "$prompt" --mode plan) ;;
esac

mkdir -p .verify
report=".verify/review-$(date +%Y%m%d-%H%M%S).md"
{
  echo "# devguard review: $what (reviewer: $with)"
  echo
} > "$report"
"${cmd[@]}" < /dev/null >> "$report" 2>&1
code=$?

verdict=$(grep -Eo 'VERDICT: (SHIP|CHANGES NEEDED)' "$report" | tail -n 1)
findings=$(grep -cE '^[-*] *\[(BLOCKER|MAJOR|MINOR)\]' "$report")
echo "devguard review [$with]: ${verdict:-no verdict} · $findings finding(s) · $report"
[ "$code" = 0 ] || echo "devguard review: $with exited $code; see $report" >&2
exit "$code"
