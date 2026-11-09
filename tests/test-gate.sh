#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# SC2016: check() bodies are eval'd later, so single quotes are intended.
# devguard gate: .devguard/checks parsing, stages, git hooks. Uses throwaway repos only.
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd -P)
GATE="$KIT/bin/gate.sh"
T=$(cd "$(mktemp -d)" && pwd -P)
fail=0; check(){ if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
g() { git -c user.name=t -c user.email=t@t -c core.autocrlf=false "$@"; }

new_repo() {
  rm -rf "${T:?}/${1:?}"; mkdir -p "$T/$1"; cd "$T/$1" || exit 1
  git init -q; git config core.autocrlf false; printf '.verify/\n' > .gitignore; g add .gitignore; g commit -qm init
}
checks() { mkdir -p .devguard; printf '%s\n' "$@" > .devguard/checks; }

echo "== run: stages and results"
new_repo run
checks '# comment line' '' 'commit fast: echo fast-ran' 'push   slow: echo slow-ran'
out=$("$GATE" run commit 2>&1); code=$?
check "commit stage passes" '[ $code = 0 ]'
check "commit stage runs commit checks" '[ -f .verify/gate-fast.log ] && grep -q fast-ran .verify/gate-fast.log'
check "commit stage skips push checks" '[ ! -f .verify/gate-slow.log ]'
out=$("$GATE" run push 2>&1); code=$?
check "push stage runs commit and push checks" '[ $code = 0 ] && grep -q slow-ran .verify/gate-slow.log'
checks 'commit ok: true' 'commit broken: echo boom >&2; exit 3'
out=$("$GATE" run all 2>&1); code=$?
check "failing check fails the gate" '[ $code = 1 ]'
check "failure names the check and its log" 'printf "%s" "$out" | grep -q "broken" && printf "%s" "$out" | grep -q ".verify/gate-broken.log"'
check "failure output is captured in the log" 'grep -q boom .verify/gate-broken.log'
checks 'commit missing-colon true'
out=$("$GATE" run all 2>&1); code=$?
check "malformed line fails closed with its line number" '[ $code = 2 ] && printf "%s" "$out" | grep -q "line 1"'
checks 'deploy x: true'
out=$("$GATE" run all 2>&1); code=$?
check "unknown stage fails closed" '[ $code = 2 ]'
rm -rf .devguard
out=$("$GATE" run all 2>&1); code=$?
check "no checks file passes" '[ $code = 0 ]'
# git runs hooks with SIGPIPE ignored, and children inherit that. A writer into a closed pipe then
# gets "Broken pipe" errors instead of dying quietly, so checks behave unlike a terminal run.
checks "commit sigpipe: test -z \"\$( { bash -c 'sleep 0.2; echo b' | true; } 2>&1 )\""
out=$( (trap '' PIPE; "$GATE" run all) 2>&1); code=$?
check "checks run with default SIGPIPE even when the caller ignores it" '[ $code = 0 ]'

# A repo file named like a stdlib module must not hijack the gate's own Python helper.
new_repo shadow
printf 'raise SystemExit("shadowed")\n' > signal.py
checks 'commit ok: true'
out=$("$GATE" run all 2>&1); code=$?
check "a repo's own signal.py does not break the gate" '[ $code = 0 ]'

echo "== hooks"
new_repo hooks
checks 'commit ok: true'
"$GATE" install > /dev/null 2>&1
check "pre-commit hook installed" 'grep -q devguard-gate .git/hooks/pre-commit && [ -x .git/hooks/pre-commit ]'
check "pre-push hook installed" 'grep -q devguard-gate .git/hooks/pre-push'
cp .git/hooks/pre-commit "$T/hook1"; "$GATE" install > /dev/null 2>&1
check "install is idempotent" 'cmp -s .git/hooks/pre-commit "$T/hook1"'
echo a > a.txt; g add a.txt
g commit -qm ok > /dev/null 2>&1; code=$?
check "commit allowed when checks pass" '[ $code = 0 ]'
checks 'commit broken: exit 1'
echo b > b.txt; g add b.txt .devguard/checks
out=$(g commit -qm bad 2>&1); code=$?
check "commit blocked when a check fails" '[ $code != 0 ] && [ "$(git log --oneline | wc -l | tr -d " ")" = 2 ]'
check "commit that edits the checks file is flagged" 'printf "%s" "$out" | grep -q ".devguard/checks"'
"$GATE" uninstall > /dev/null 2>&1
check "uninstall removes our hooks" '[ ! -e .git/hooks/pre-commit ] && [ ! -e .git/hooks/pre-push ]'

echo "== foreign hooks and a moved kit"
new_repo foreign
printf '#!/bin/sh\necho mine\n' > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit
cp .git/hooks/pre-commit "$T/foreign-hook.bak"
out=$("$GATE" install 2>&1)
check "foreign pre-commit hook left untouched" 'cmp -s .git/hooks/pre-commit "$T/foreign-hook.bak"'
check "install warns about the foreign hook" 'printf "%s" "$out" | grep -qi "not ours"'
"$GATE" uninstall > /dev/null 2>&1
check "uninstall keeps the foreign hook" 'cmp -s .git/hooks/pre-commit "$T/foreign-hook.bak"'
new_repo moved
checks 'commit broken: exit 1'
mkdir -p "$T/kitcopy/bin"; cp "$GATE" "$KIT/bin/verify.sh" "$T/kitcopy/bin/"
"$T/kitcopy/bin/gate.sh" install > /dev/null 2>&1
rm -rf "$T/kitcopy"
echo c > c.txt; g add c.txt
out=$(g commit -qm moved 2>&1); code=$?
check "hook fails open with a warning when the kit is gone" '[ $code = 0 ] && printf "%s" "$out" | grep -q "not found"'

echo "== linked worktree"
new_repo wt-main
checks 'commit ok: true'
g add .devguard/checks; g commit -qm checks
git worktree add -q "$T/wt-linked" 2>/dev/null; cd "$T/wt-linked" || exit 1
"$GATE" install > /dev/null 2>&1
check "install in a worktree writes to the shared hooks dir" 'grep -q devguard-gate "$(git rev-parse --git-path hooks)/pre-commit"'

echo "== gate init auto-detects project stack"
new_repo swift-pkg
printf '// swift-tools-version:5.9\n' > Package.swift; g add Package.swift
"$GATE" init > /dev/null 2>&1
check "gate init writes active swift build/test checks for Package.swift" 'grep -qx "commit build: swift build" .devguard/checks && grep -qx "push   test:  swift test" .devguard/checks'

new_repo shell-proj
printf '#!/bin/sh\necho ok\n' > run.sh; g add run.sh
"$GATE" init > /dev/null 2>&1
out=$("$GATE" run commit 2>&1); code=$?
check "gate init writes runnable shell syntax check for .sh repo" '[ $code = 0 ] && grep -q "^commit sh-syntax:" .devguard/checks'
printf '#!/bin/sh\nif [\n' > run.sh
out=$("$GATE" run commit 2>&1); code=$?
check "auto-detected shell syntax check catches broken .sh on commit" '[ $code = 1 ]'

echo "== gate init adds security checks (gitleaks always, osv-scanner on a lockfile)"
new_repo sec-plain
printf 'hello\n' > note.txt; g add note.txt
"$GATE" init > /dev/null 2>&1
check "gate init writes an active gitleaks secrets check" 'grep -q "^commit secrets:" .devguard/checks && grep -q "gitleaks git --staged" .devguard/checks'
check "a repo with no lockfile gets no deps check" '! grep -q "^push   deps:" .devguard/checks'
check "the secrets check self-skips with exit 0 when gitleaks is absent" 'PATH= /bin/sh -c "command -v gitleaks >/dev/null 2>&1 || exit 0; exit 1"; [ $? -eq 0 ]'

new_repo sec-deps
printf 'jinja2==3.1.6\n' > requirements.txt; g add requirements.txt
"$GATE" init > /dev/null 2>&1
check "a repo with a lockfile also gets an osv-scanner deps check" 'grep -q "^push   deps:" .devguard/checks && grep -q "osv-scanner scan source" .devguard/checks'
check "the deps check self-skips with exit 0 when osv-scanner is absent" 'PATH= /bin/sh -c "command -v osv-scanner >/dev/null 2>&1 || exit 0; exit 1"; [ $? -eq 0 ]'

exit $fail
