#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# SC2016: check() bodies are eval'd later, so single quotes are intended.
# devguard review: reviewer selection, read-only flags, prompt contents, report file.
# Stub reviewer CLIs record their arguments; nothing is sent to a real model.
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd -P)
REVIEW="$KIT/bin/review.sh"
T=$(cd "$(mktemp -d)" && pwd -P)
fail=0; check(){ if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
g() { git -c user.name=t -c user.email=t@t "$@"; }

mkdir -p "$T/bin"
for c in claude gemini agy; do
  # Records argv (one per line) and stdin, then answers like a reviewer would.
  printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a"; done > "%s/%s.args"\ncat > "%s/%s.stdin"\necho "- [MAJOR] a.txt:1 — stub finding"\necho "VERDICT: CHANGES NEEDED"\n' \
    "$T" "$c" "$T" "$c" > "$T/bin/$c"
  chmod +x "$T/bin/$c"
done
export PATH="$T/bin:/usr/bin:/bin"
unset DEVGUARD_REVIEWER

mkdir -p "$T/repo" && cd "$T/repo" || exit 1
git init -q; printf '.verify/\n' > .gitignore; echo one > a.txt; g add .; g commit -qm init

out=$("$REVIEW" 2>&1); code=$?
check "clean tree with one commit reviews HEAD" '[ $code = 0 ] && grep -q "a.txt" "$T/claude.args"'
rm -f "$T"/*.args

echo two >> a.txt
out=$("$REVIEW" 2>&1); code=$?
check "default reviewer is claude when present" '[ -f "$T/claude.args" ]'
check "claude runs read-only (plan mode)" 'grep -qx -- "--permission-mode" "$T/claude.args" && grep -qx plan "$T/claude.args"'
check "prompt carries the uncommitted diff" 'grep -q "^+two" "$T/claude.args"'
check "prompt asks for a verdict line" 'grep -q "VERDICT: SHIP" "$T/claude.args"'
report=$(ls .verify/review-*.md 2>/dev/null | head -n 1)
check "report saved under .verify" '[ -n "$report" ] && grep -q "stub finding" "$report"'
check "summary names verdict and report" 'printf "%s" "$out" | grep -q "CHANGES NEEDED" && printf "%s" "$out" | grep -q "review-"'

rm -f "$T"/*.args
"$REVIEW" --with gemini > /dev/null 2>&1
check "--with gemini uses gemini read-only" '[ -f "$T/gemini.args" ] && grep -qx -- "--approval-mode" "$T/gemini.args" && grep -qx plan "$T/gemini.args"'
"$REVIEW" --with agy > /dev/null 2>&1
check "--with agy uses agy plan mode" '[ -f "$T/agy.args" ] && grep -qx -- "--mode" "$T/agy.args" && grep -qx plan "$T/agy.args"'
DEVGUARD_REVIEWER=gemini "$REVIEW" > /dev/null 2>&1; rm -f "$T/gemini.args"
DEVGUARD_REVIEWER=gemini "$REVIEW" > /dev/null 2>&1
check "DEVGUARD_REVIEWER picks the default" '[ -f "$T/gemini.args" ]'

"$REVIEW" --with nobody > /dev/null 2>&1; code=$?
check "unknown reviewer rejected (64)" '[ $code = 64 ]'
printf '#!/bin/sh\necho "Not logged in · Please run /login"\nexit 1\n' > "$T/bin/claude"
out=$("$REVIEW" --with claude 2>&1); code=$?
check "signed-out reviewer exits non-zero with a sign-in hint" '[ $code = 1 ] && printf "%s" "$out" | grep -q "not signed in"'
rm "$T/bin/claude"
out=$("$REVIEW" --with claude 2>&1); code=$?
check "missing reviewer CLI is a clear error" '[ $code = 69 ] && printf "%s" "$out" | grep -q "claude"'

g add .; g commit -qm two; echo three >> a.txt; g add .; g commit -qm three
rm -f "$T"/*.args
"$REVIEW" --with gemini --base HEAD~2 > /dev/null 2>&1
check "--base reviews the whole range" 'grep -q "^+two" "$T/gemini.args" && grep -q "^+three" "$T/gemini.args"'

exit $fail
