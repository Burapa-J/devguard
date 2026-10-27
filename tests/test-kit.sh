#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2155,SC2034,SC2329
# SC2016: check() bodies are eval'd later, so single quotes are intended.
# Runs install/uninstall against a throwaway HOME. Never touches your real home directory.
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd -P)
export HOME=$(mktemp -d)
export PATH="$HOME/.local/bin:$PATH"
fail=0; check(){ if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
# Tree snapshot that never follows symlinks (BSD and GNU diff -r both do, and macOS reports
# "Directory loop detected" when two links share a target). Records type, link target, checksum.
snap() {
  (cd "$1" && find . -path ./.agent-kit-backup -prune -o -print | LC_ALL=C sort | while IFS= read -r p; do
    if [ -L "$p" ]; then echo "L $p -> $(readlink "$p")"
    elif [ -d "$p" ]; then echo "D $p"
    else echo "F $p $(cksum < "$p")"; fi
  done)
}
same_tree() { [ "$(snap "$1")" = "$(snap "$2")" ]; }

# Seed: existing user content that must survive untouched
mkdir -p "$HOME/.claude"
printf '# My rules\n- be nice\n' > "$HOME/.claude/CLAUDE.md"
echo '{"model":"opus","hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"/usr/local/bin/mine.sh"}]}]}}' | jq . > "$HOME/.claude/settings.json"
mkdir -p "$HOME/.gemini/antigravity-cli/skills/verified-dev"   # foreign real dir: must be skipped, not replaced
echo "foreign" > "$HOME/.gemini/antigravity-cli/skills/verified-dev/SKILL.md"
cp -R "$HOME" "$HOME.orig"

echo "== dry-run"; "$KIT/install.sh" --dry-run --with-hooks --with=none
check "dry-run changes nothing" 'same_tree "$HOME" "$HOME.orig"'

echo "== install"; "$KIT/install.sh" --with-hooks --with=none 2>&1
check "user text kept in CLAUDE.md" 'grep -qx -- "- be nice" "$HOME/.claude/CLAUDE.md"'
check "block in CLAUDE.md" 'grep -qx "<!-- agent-kit:begin -->" "$HOME/.claude/CLAUDE.md"'
check "block in GEMINI.md" 'grep -q "verified-dev" "$HOME/.gemini/GEMINI.md"'
check "block in copilot" 'grep -q "verified-dev" "$HOME/.copilot/copilot-instructions.md"'
check "claude skill link" '[ "$(readlink "$HOME/.claude/skills/verified-dev")" = "$KIT/skills/verified-dev" ]'
check "no duplicate copilot skill" '[ ! -e "$HOME/.copilot/skills/verified-dev" ]'
check "antigravity skill link" '[ -L "$HOME/.gemini/config/skills/verified-dev" ]'
check "foreign dir untouched" '[ ! -L "$HOME/.gemini/antigravity-cli/skills/verified-dev" ] && grep -q foreign "$HOME/.gemini/antigravity-cli/skills/verified-dev/SKILL.md"'
check "user hook kept" 'jq -e ".hooks.SessionStart[] | select(.matcher==\"startup\")" "$HOME/.claude/settings.json" >/dev/null'
check "our hook added once" '[ "$(jq "[.hooks.SessionStart[].hooks[] | select(.command==\"$KIT/hooks/remind.sh\")] | length" "$HOME/.claude/settings.json")" = 1 ]'
check "model key kept" '[ "$(jq -r .model "$HOME/.claude/settings.json")" = opus ]'
check "backup made" 'ls "$HOME"/.agent-kit-backup/*/.claude/CLAUDE.md >/dev/null 2>&1'
cp -R "$HOME" "$HOME.after1"; rm -rf "$HOME.after1/.agent-kit-backup"

echo "== install again"; sleep 1; "$KIT/install.sh" --with-hooks --with=none 2>&1
tmp=$(mktemp -d); cp -R "$HOME/." "$tmp"; rm -rf "$tmp/.agent-kit-backup"
check "re-install is idempotent" 'same_tree "$tmp" "$HOME.after1"'

echo "== agent-verify"; cd "$(mktemp -d)" || exit 1
agent-verify ok -- sh -c 'echo hello; echo err >&2'; code=$?
check "success exit 0" '[ $code = 0 ]'
check "stdout+stderr captured" 'grep -qx hello .verify/ok.log && grep -qx err .verify/ok.log'
agent-verify bad -- sh -c 'echo boom; exit 3'; code=$?
check "failure exit propagated" '[ $code = 3 ]'
check "exit recorded in log" 'grep -qx "# exit: 3" .verify/bad.log'
agent-verify ../x -- true 2>/dev/null; check "path traversal rejected" '[ $? = 64 ]'
"$KIT/hooks/remind.sh" | grep -q verified-dev; check "hook prints reminder" '[ $? = 0 ]'

echo "== uninstall"; "$KIT/uninstall.sh" 2>&1
rm -rf "$HOME/.agent-kit-backup"
check "CLAUDE.md byte-identical to original" 'cmp -s "$HOME/.claude/CLAUDE.md" "$HOME.orig/.claude/CLAUDE.md"'
check "settings.json identical to original" 'cmp -s "$HOME/.claude/settings.json" "$HOME.orig/.claude/settings.json"'
check "whole HOME restored" 'same_tree "$HOME" "$HOME.orig"'
echo "== uninstall again (no-op)"; "$KIT/uninstall.sh" 2>&1
exit $fail
