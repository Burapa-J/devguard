#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2155,SC2034,SC2329
# SC2016: check() bodies are eval'd later, so single quotes are intended.
# Component install/wire/unwire/purge against a throwaway HOME with stub npm, python3, node and
# codegraph on PATH. Nothing is downloaded and your real home directory is never touched.
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd -P)
export HOME=$(cd "$(mktemp -d)" && pwd -P)
STUB=$(cd "$(mktemp -d)" && pwd -P)
export STUB_LOG="$STUB/calls.log"
export PATH="$STUB/bin:$HOME/.local/bin:/usr/bin:/bin"
fail=0; check(){ if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
snap() {
  (cd "$1" && find . -path ./.agent-kit-backup -prune -o -print | LC_ALL=C sort | while IFS= read -r p; do
    if [ -L "$p" ]; then echo "L $p -> $(readlink "$p")"
    elif [ -d "$p" ]; then echo "D $p"
    else echo "F $p $(cksum < "$p")"; fi
  done)
}
same_tree() { [ "$(snap "$1")" = "$(snap "$2")" ]; }
calls() { grep -c "$1" "$STUB_LOG" 2>/dev/null || true; }

# ---- stubs -------------------------------------------------------------------------------------
mkdir -p "$STUB/bin"
cat > "$STUB/bin/npm" <<'EOF'
#!/bin/sh
echo "npm $*" >> "$STUB_LOG"
d=$(dirname "$0")
case "$1 $2 $3" in
  "install -g @colbymchenry/codegraph@"*) cp "$d/codegraph.real" "$d/codegraph"; chmod +x "$d/codegraph"; echo "${3##*@}" > "$d/cg.ver" ;;
  "install -g context-mode@"*) printf '#!/bin/sh\n' > "$d/context-mode"; chmod +x "$d/context-mode" ;;
  "uninstall -g @colbymchenry/codegraph") rm -f "$d/codegraph" ;;
  "uninstall -g context-mode") rm -f "$d/context-mode" ;;
esac
EOF
# Fake codegraph: writes/removes its MCP entry the way the real installer does.
cat > "$STUB/bin/codegraph.real" <<'EOF'
#!/bin/sh
echo "codegraph $*" >> "$STUB_LOG"
d=$(dirname "$0")
put() { f=$1; k=$2; mkdir -p "$(dirname "$f")"; [ -f "$f" ] || echo '{}' > "$f"
        jq --arg k "$k" '.[$k].codegraph = {"command":"codegraph","args":["serve","--mcp"]}' "$f" > "$f.t" && mv "$f.t" "$f"; }
del() { f=$1; k=$2; [ -f "$f" ] || return 0
        jq --arg k "$k" 'del(.[$k].codegraph) | if .[$k] == {} then del(.[$k]) else . end' "$f" > "$f.t" && mv "$f.t" "$f"
        [ "$(jq -c . "$f")" = "{}" ] && rm -f "$f"; return 0; }
VS="$HOME/.config/Code/User/mcp.json"; [ "$(uname -s)" = Darwin ] && VS="$HOME/Library/Application Support/Code/User/mcp.json"
case "$1" in
  --version) [ -f "$d/cg.ver" ] && cat "$d/cg.ver" || echo "1.6.2" ;;
  install) case "$2" in
             --target=claude) put "$HOME/.claude.json" mcpServers ;;
             --target=copilot-vscode) put "$VS" servers ;;
             --target=antigravity) put "$HOME/.gemini/config/mcp_config.json" mcpServers ;;
           esac ;;
  uninstall) del "$HOME/.claude.json" mcpServers; del "$VS" servers; del "$HOME/.gemini/config/mcp_config.json" mcpServers ;;
  init) mkdir -p .codegraph ;;
esac
EOF
chmod +x "$STUB/bin/codegraph.real"
cat > "$STUB/bin/python3" <<'EOF'
#!/bin/sh
echo "python3 $*" >> "$STUB_LOG"
if [ "$1 $2" = "-m venv" ]; then
  mkdir -p "$3/bin"
  printf '#!/bin/sh\necho "pip $*" >> "$STUB_LOG"\n' > "$3/bin/pip"
  printf '#!/bin/sh\n' > "$3/bin/python"
  printf '#!/bin/sh\necho "pjm $*" >> "$STUB_LOG"\n[ "$1" = init ] && mkdir -p .projectmem\n' > "$3/bin/pjm"
  cp "$3/bin/pjm" "$3/bin/projectmem"
  chmod +x "$3/bin/"*
fi
EOF
printf '#!/bin/sh\necho 22\n' > "$STUB/bin/node"
cat > "$STUB/bin/brew" <<'EOF'
#!/bin/sh
echo "brew $*" >> "$STUB_LOG"
d=$(dirname "$0")
case "$1 $2" in
  "install rtk") cp "$d/rtk.real" "$d/rtk"; chmod +x "$d/rtk" ;;
  "uninstall rtk") rm -f "$d/rtk" ;;
esac
EOF
cat > "$STUB/bin/rtk.real" <<'EOF'
#!/bin/sh
echo "rtk $*" >> "$STUB_LOG"
case "$*" in
  "gain") exit 0 ;;
  "telemetry disable") exit 0 ;;
  "init -g --auto-patch") mkdir -p "$HOME/.claude/hooks"; : > "$HOME/.claude/hooks/rtk-rewrite.sh" ;;
  "init -g --copilot") : ;;
  "init -g --agent antigravity") mkdir -p "$HOME/.gemini/config/plugins/rtk/rules"; : > "$HOME/.gemini/config/plugins/rtk/plugin.json"; : > "$HOME/.gemini/config/plugins/rtk/hooks.json"; : > "$HOME/.gemini/config/plugins/rtk/rules/AGENTS.md" ;;
  "init -g --agent antigravity --uninstall") rm -rf "$HOME/.gemini/config/plugins/rtk"; rmdir "$HOME/.gemini/config/plugins" 2>/dev/null || true ;;
  "init -g --uninstall") rm -f "$HOME/.claude/hooks/rtk-rewrite.sh"; rmdir "$HOME/.claude/hooks" 2>/dev/null || true ;;
esac
EOF
chmod +x "$STUB/bin/npm" "$STUB/bin/python3" "$STUB/bin/node" "$STUB/bin/brew" "$STUB/bin/rtk.real"

# ---- seed user content -------------------------------------------------------------------------
echo '{"numStartups":7,"mcpServers":{"mine":{"command":"my-server"}}}' | jq . > "$HOME/.claude.json"
mkdir -p "$HOME/.claude"
cp -R "$HOME" "$HOME.orig"
CJ="$HOME/.claude.json"
AG="$HOME/.gemini/config/mcp_config.json"
VS="$HOME/.config/Code/User/mcp.json"; [ "$(uname -s)" = Darwin ] && VS="$HOME/Library/Application Support/Code/User/mcp.json"
has() { jq -e --arg k "$2" --arg n "$3" '.[$k] | has($n)' "$1" >/dev/null 2>&1; }

echo "== unknown component"
"$KIT/install.sh" --with=bogus >/dev/null 2>&1; code=$?
check "unknown component rejected (64)" '[ $code = 64 ]'
"$KIT/install.sh" --with=none --auto-project="$HOME/no such dir" >/dev/null 2>&1; code=$?
check "bad --auto-project rejected before any change" '[ $code = 64 ] && same_tree "$HOME" "$HOME.orig"'

echo "== dry-run with default components (codegraph,projectmem,rtk) + context-mode"
"$KIT/install.sh" --dry-run --with=codegraph,projectmem,rtk,context-mode > /dev/null 2>&1
check "dry-run changes nothing" 'same_tree "$HOME" "$HOME.orig"'
check "dry-run calls no installer" '[ ! -s "$STUB_LOG" ]'

echo "== install default components + context-mode"
"$KIT/install.sh" --with=codegraph,projectmem,rtk,context-mode > "$STUB/install1.log" 2>&1; code=$?
check "install exit 0" '[ $code = 0 ]'
check "codegraph installed via pinned npm" '[ "$(calls "npm install -g @colbymchenry/codegraph@")" = 1 ]'
check "projectmem venv created" '[ -x "$HOME/.local/share/agent-kit/projectmem-venv/bin/pjm" ]'
check "pjm linked on PATH" '[ -L "$HOME/.local/bin/pjm" ]'
check "rtk installed via brew and wired" '[ "$(calls "brew install rtk")" = 1 ] && [ -f "$HOME/.claude/hooks/rtk-rewrite.sh" ] && [ -f "$HOME/.gemini/config/plugins/rtk/plugin.json" ] && [ -f "$HOME/.gemini/config/plugins/rtk/hooks.json" ] && [ -f "$HOME/.gemini/config/plugins/rtk/rules/AGENTS.md" ]'
for a in "$CJ:mcpServers" "$VS:servers" "$AG:mcpServers"; do
  f=${a%:*}; k=${a##*:}
  for n in codegraph projectmem context-mode; do
    check "$n wired in $(basename "$f")" 'has "$f" "$k" "$n"'
  done
done
check "projectmem points at venv python" '[ "$(jq -r ".mcpServers.projectmem.command" "$CJ")" = "$HOME/.local/share/agent-kit/projectmem-venv/bin/python" ]'
check "user MCP server kept" 'has "$CJ" mcpServers mine'
check "unrelated .claude.json key kept" '[ "$(jq .numStartups "$CJ")" = 7 ]'
check "state recorded" '[ -f "$HOME/.agent-kit/components/projectmem/installed-by-kit" ] && grep -qx antigravity "$HOME/.agent-kit/components/codegraph/wired" && grep -qx claude "$HOME/.agent-kit/components/rtk/wired"'

echo "== re-install"
cp "$STUB_LOG" "$STUB/before"; snap "$HOME" > "$STUB/snap1"
"$KIT/install.sh" --with=codegraph,projectmem,rtk,context-mode > /dev/null 2>&1
check "no reinstall of present CLIs" '! diff "$STUB/before" "$STUB_LOG" | grep -q "npm install\|venv\|brew install"'
check "re-install leaves files identical" '[ "$(snap "$HOME")" = "$(cat "$STUB/snap1")" ]'

echo "== status"
"$KIT/status.sh" > "$STUB/status.log" 2>&1
check "status lists wired components" 'grep -q "projectmem: CLI installed, managed by devguard" "$STUB/status.log" && grep -q "rtk: CLI installed, managed by devguard" "$STUB/status.log"'

echo "== devguard-project init"
repo=$(mktemp -d); (cd "$repo" && git init -q && printf 'build/' > .gitignore && devguard-project init > "$STUB/proj.log" 2>&1); code=$?
check "project init exit 0" '[ $code = 0 ]'
check "codegraph index created" '[ -d "$repo/.codegraph" ]'
check "projectmem initialized" '[ -d "$repo/.projectmem" ]'
check ".verify/ added on its own line" '[ "$(cat "$repo/.gitignore")" = "$(printf "build/\n.verify/")" ]'
(cd "$repo" && devguard-project init > /dev/null 2>&1)
check "project init idempotent" '[ "$(grep -c "^.verify/$" "$repo/.gitignore")" = 1 ]'

echo "== uninstall (keep CLIs)"
"$KIT/uninstall.sh" > "$STUB/un1.log" 2>&1; code=$?
check "uninstall exit 0" '[ $code = 0 ]'
check "codegraph unwired once" '[ "$(calls "codegraph uninstall")" = 1 ]'
check "our MCP entries gone, user entry kept" '[ "$(jq -c ".mcpServers" "$CJ")" = "{\"mine\":{\"command\":\"my-server\"}}" ]'
check "antigravity MCP file removed" '[ ! -e "$AG" ]'
check "CLIs kept without --purge" '[ -x "$STUB/bin/codegraph" ] && [ -d "$HOME/.local/share/agent-kit/projectmem-venv" ]'
check "wiring state cleared" '[ -z "$(find "$HOME/.agent-kit" -name wired 2>/dev/null)" ]'
check "ownership kept for later purge" '[ -f "$HOME/.agent-kit/components/codegraph/installed-by-kit" ]'

echo "== reinstall, then uninstall --purge"
"$KIT/install.sh" --with=codegraph,projectmem,rtk,context-mode > /dev/null 2>&1
check "reinstall did not reinstall CLIs" '[ "$(calls "npm install -g @colbymchenry/codegraph@")" = 1 ] && [ "$(calls "brew install rtk")" = 1 ]'
"$KIT/uninstall.sh" --purge > "$STUB/un2.log" 2>&1
check "kit-installed codegraph removed on purge" '[ ! -e "$STUB/bin/codegraph" ] && [ "$(calls "npm uninstall -g @colbymchenry/codegraph")" = 1 ]'
check "kit-installed rtk removed on purge" '[ ! -e "$STUB/bin/rtk" ] && [ "$(calls "brew uninstall rtk")" = 1 ]'
check "kit-installed context-mode removed on purge" '[ ! -e "$STUB/bin/context-mode" ]'
check "kit-installed projectmem venv removed on purge" '[ ! -e "$HOME/.local/share/agent-kit" ] && [ ! -e "$HOME/.local/bin/pjm" ]'
check "all state gone after purge" '[ ! -e "$HOME/.agent-kit" ]'

echo "== user-installed CLI survives purge"
cp "$STUB/bin/codegraph.real" "$STUB/bin/codegraph"
"$KIT/install.sh" --with=codegraph > /dev/null 2>&1
"$KIT/uninstall.sh" --purge > "$STUB/un3.log" 2>&1
check "user codegraph kept on purge" '[ -x "$STUB/bin/codegraph" ] && grep -q "kept       codegraph CLI (not installed" "$STUB/un3.log"'
check "but its wiring removed" '! has "$CJ" mcpServers codegraph'

echo "== automatic project setup, kit path with a space"
SKIT="$STUB/kit with space"; mkdir -p "$SKIT"; cp -R "$KIT/." "$SKIT/"
export AGENT_KIT_FORCE_LAUNCHD=1 AGENT_KIT_LAUNCHD_DIR="$HOME/Library/LaunchAgents"
printf '#!/bin/sh\necho "launchctl $*" >> "$STUB_LOG"\n' > "$STUB/bin/launchctl"; chmod +x "$STUB/bin/launchctl"
printf '# my zsh config\nalias ll="ls -l"\n' > "$HOME/.zshrc"; cp "$HOME/.zshrc" "$STUB/zshrc.orig"
DEV="$HOME/Dev Projects"; mkdir -p "$DEV/app" "$DEV/group/lib" "$HOME/elsewhere/other"
for r in "$DEV/app" "$DEV/group/lib" "$HOME/elsewhere/other"; do (cd "$r" && git init -q); done
touch "$DEV/group/lib/.agent-kit-skip"
"$SKIT/install.sh" --with=codegraph,projectmem --auto-project="$DEV" > "$STUB/auto-install.log" 2>&1; code=$?
check "install with --auto-project exit 0" '[ $code = 0 ]'
check "auto root recorded" '[ "$(cat "$HOME/.agent-kit/auto-roots")" = "$DEV" ]'
# Run every SessionStart hook command exactly as Claude Code would: through a shell.
run_hooks() { jq -r ".hooks.SessionStart[] | select(.matcher==\"$1\") | .hooks[].command" "$HOME/.claude/settings.json" |
  while IFS= read -r c; do (cd "$2" && CLAUDE_PROJECT_DIR="$2" sh -c "$c"); done; }
check "hooks on by default; compact hook runs from spaced path" 'run_hooks compact "$DEV/app" | grep -q verified-dev'
out=$(run_hooks startup "$DEV/app"); sleep 2
check "startup hook announces setup" 'printf "%s" "$out" | grep -q "Setting up this repository"'
check "auto setup indexed repo under root" '[ -d "$DEV/app/.codegraph" ] && [ -d "$DEV/app/.projectmem" ] && grep -qx ".verify/" "$DEV/app/.gitignore"'
check "auto setup quiet once ready" '[ -z "$(run_hooks startup "$DEV/app")" ]'
check "repo outside roots untouched" '[ -z "$(run_hooks startup "$HOME/elsewhere/other")" ] && [ ! -e "$HOME/elsewhere/other/.gitignore" ]'
check ".agent-kit-skip respected" '[ -z "$(run_hooks startup "$DEV/group/lib")" ] && [ ! -e "$DEV/group/lib/.codegraph" ]'

echo "== zsh cd hook (real zsh)"
check "zshrc block added, user lines kept" 'grep -qx "# >>> agent-kit >>>" "$HOME/.zshrc" && grep -qx "alias ll=\"ls -l\"" "$HOME/.zshrc"'
if command -v zsh >/dev/null 2>&1; then
  mkdir -p "$DEV/viazsh" && (cd "$DEV/viazsh" && git init -q)
  zsh -c 'source "$HOME/.zshrc"; cd "$1"; sleep 3' zsh "$DEV/viazsh" >/dev/null 2>&1
  check "cd in zsh sets up repo" '[ -d "$DEV/viazsh/.codegraph" ] && [ -d "$DEV/viazsh/.projectmem" ]'
  zsh -c 'source "$HOME/.zshrc"; cd "$1"; sleep 1' zsh "$HOME/elsewhere/other" >/dev/null 2>&1
  check "cd outside roots does nothing" '[ ! -e "$HOME/elsewhere/other/.codegraph" ]'
else
  echo "SKIP zsh not installed"
fi

echo "== launchd periodic scan"
P="$HOME/Library/LaunchAgents/com.agent-kit.scan.plist"
check "launchd plist written and loaded" '[ -f "$P" ] && grep -q "launchctl bootstrap" "$STUB_LOG"'
check "plist is valid XML pointing at the kit" 'python3 -c "import sys,xml.dom.minidom as m; m.parse(sys.argv[1])" "$P" && grep -q "kit with space/bin/project.sh" "$P"'
mkdir -p "$DEV/new-from-gui" && (cd "$DEV/new-from-gui" && git init -q)
devguard-project scan > "$STUB/scan.log" 2>&1
check "scan sets up a repo nobody opened from a shell" '[ -d "$DEV/new-from-gui/.codegraph" ] && grep -q "setting up $DEV/new-from-gui" "$STUB/scan.log"'
check "scan skips ready and skipped repos" '! grep -q "setting up $DEV/app$" "$STUB/scan.log" && ! grep -q "group/lib" "$STUB/scan.log"'
check "scan is silent when nothing to do" '[ -z "$(devguard-project scan 2>&1)" ]'

echo "== devguard command"
check "devguard status works" 'devguard status | grep -q "ok   auto setup (Claude Code)"'
check "status shows zsh and launchd" 'devguard status | grep -q "ok   auto setup on cd (zsh)" && devguard status | grep -q "ok   auto setup scan (launchd)"'
rm "$DEV/group/lib/.agent-kit-skip"
devguard init --all > "$STUB/initall.log" 2>&1
check "devguard init --all sets up nested repos" '[ -d "$DEV/group/lib/.codegraph" ] && grep -q "Done: 4 repositories" "$STUB/initall.log"'
(cd "$HOME/elsewhere/other" && devguard skip > /dev/null)
check "devguard skip creates marker" '[ -f "$HOME/elsewhere/other/.agent-kit-skip" ]'
check "unknown command rejected" '! devguard frobnicate 2>/dev/null'

echo "== devguard doctor (detect and fix all 7 issue types)"
# Seed all 7 failure modes into the throwaway HOME:
printf '#!/bin/sh\necho "tokless $*" >> "$STUB_LOG"\n' > "$HOME/.local/bin/tokless"; chmod +x "$STUB/bin/tokless" 2>/dev/null || chmod +x "$HOME/.local/bin/tokless"
printf '# tokless\n# >>> tokless path >>>\nPATH=":"\n# <<< tokless path <<<\n' >> "$HOME/.zshrc"
ln -s "$HOME/nonexistent-target" "$HOME/.local/bin/broken-link"
ln -s "$HOME/nonexistent-uv" "$HOME/.local/bin/pjm-mcp"
jq '.enabledPlugins = {"caveman@caveman":true,"ponytail@ponytail":true} | .extraKnownMarketplaces = {"caveman":{},"ponytail":{}} | .env = {"ANTHROPIC_BASE_URL":"http://127.0.0.1:8787"}' "$HOME/.claude/settings.json" > "$STUB/s.json" && mv "$STUB/s.json" "$HOME/.claude/settings.json"
: > "$HOME/.claude/.caveman-active"
: > "$HOME/.claude/.caveman-history.jsonl"
mkdir -p "$HOME/.gemini/config/skills/caveman" "$HOME/.config/opencode/skills/caveman" "$HOME/.gemini/antigravity" "$HOME/.cursor/rules"
echo '{"plugin":["./plugins/caveman/plugin.js","@dietrichgebert/ponytail"],"mcp":{"servers":{"projectmem":{"type":"local","command":["pjm"],"disabled":false}}}}' > "$HOME/.config/opencode/opencode.jsonc"
printf '<!-- agent-kit:begin -->\n# legacy potless rule\n<!-- agent-kit:end -->\n' > "$HOME/.cursor/rules/potless.mdc"
echo '{"mcpServers":{"projectmem":{"command":"old"}}}' > "$HOME/.gemini/antigravity/mcp_config.json"
"$SKIT/install.sh" --with=codegraph,projectmem,rtk --auto-project="$DEV" > /dev/null 2>&1
rm -rf "$HOME/.gemini/config/plugins/rtk"
printf '<!-- agent-kit:begin -->\n# stale rules\n<!-- agent-kit:end -->\n' > "$HOME/.claude/CLAUDE.md"
echo "1.6.0" > "$STUB/bin/cg.ver"
devguard doctor > "$STUB/doc1.log" 2>&1; code=$?
check "doctor detects all 7 issues and exits 1" '[ $code = 1 ] && grep -q "Found 7 issue(s)" "$STUB/doc1.log"'
devguard doctor --fix > "$STUB/docfix.log" 2>&1; code=$?
check "doctor --fix repairs all 7 issues" '[ $code = 0 ] && grep -q "7 repaired" "$STUB/docfix.log"'
check "doctor ran tokless proxy stop and disable before removing" 'grep -q "tokless proxy stop" "$STUB_LOG" && grep -q "tokless disable" "$STUB_LOG"'
check "doctor cleaned ANTHROPIC_BASE_URL and extraKnownMarketplaces" '! jq -e ".env or .extraKnownMarketplaces or .enabledPlugins" "$HOME/.claude/settings.json" >/dev/null 2>&1'
check "doctor cleaned opencode.jsonc plugins and legacy potless.mdc" '! jq -e ".plugin" "$HOME/.config/opencode/opencode.jsonc" >/dev/null 2>&1 && [ ! -e "$HOME/.cursor/rules/potless.mdc" ] && [ ! -e "$HOME/.claude/.caveman-history.jsonl" ]'
rm -rf "$HOME/.config/opencode" "$HOME/.cursor"
devguard doctor > "$STUB/doc2.log" 2>&1; code=$?
check "doctor clean after --fix" '[ $code = 0 ] && grep -q "0 issues" "$STUB/doc2.log" && [ "$(cat "$STUB/bin/cg.ver")" = "1.6.2" ]'

echo "== turn automatic setup off"
"$SKIT/install.sh" --with=codegraph,projectmem --auto-project=none > "$STUB/auto-off.log" 2>&1
check "auto off removes zsh block, plist and roots" '! grep -q "agent-kit" "$HOME/.zshrc" && [ ! -e "$P" ] && [ ! -e "$HOME/.agent-kit/auto-roots" ]'
check "zshrc restored exactly" 'cmp -s "$HOME/.zshrc" "$STUB/zshrc.orig"'
check "auto hook removed, compaction hook kept" '! grep -q "project.sh" "$HOME/.claude/settings.json" && grep -q "remind.sh" "$HOME/.claude/settings.json"'

"$SKIT/uninstall.sh" --purge > "$STUB/auto-un.log" 2>&1
check "uninstall removes all hooks" '[ ! -e "$HOME/.claude/settings.json" ] || ! grep -q "kit with space" "$HOME/.claude/settings.json"'
check "auto state removed" '[ ! -e "$HOME/.agent-kit" ]'
rm -rf "$DEV" "$HOME/elsewhere" "$HOME/.zshrc"

echo "== zero-config default: ~/Developer"
mkdir -p "$HOME/Developer/one" && (cd "$HOME/Developer/one" && git init -q)
"$KIT/install.sh" --with=none > "$STUB/default.log" 2>&1
check "default auto root is ~/Developer" '[ "$(cat "$HOME/.agent-kit/auto-roots")" = "$HOME/Developer" ]'
"$KIT/install.sh" --with=none > /dev/null 2>&1
check "re-install keeps previous roots" '[ "$(cat "$HOME/.agent-kit/auto-roots")" = "$HOME/Developer" ]'
"$KIT/uninstall.sh" > /dev/null 2>&1
rm -rf "$HOME/Developer" "$HOME/.zshrc"

echo "== bootstrap through a pipe"
BK="$STUB/bootstrap-kit"; cp -R "$KIT/." "$BK"
git -C "$BK" -c user.name=t -c user.email=t@t commit -qam wip --allow-empty >/dev/null 2>&1
git -C "$BK" remote set-url origin "$BK" 2>/dev/null || git -C "$BK" remote add origin "$BK"
git -C "$BK" fetch -q origin 2>/dev/null; git -C "$BK" branch -q -u origin/main main 2>/dev/null
cat "$KIT/bootstrap.sh" | AGENT_KIT_DIR="$BK" bash -s -- --with=none --auto-project=none > "$STUB/boot.log" 2>&1; code=$?
check "bootstrap via pipe exit 0" '[ $code = 0 ] && grep -q "Done. Open a new terminal" "$STUB/boot.log"'
check "bootstrap installed devguard command" '[ "$(readlink "$HOME/.local/bin/devguard")" = "$BK/bin/devguard" ]'
"$BK/uninstall.sh" > /dev/null 2>&1
rm -f "$HOME/.zshrc"
unset AGENT_KIT_FORCE_LAUNCHD AGENT_KIT_LAUNCHD_DIR
rmdir "$HOME/Library/Application Support" "$HOME/Library" 2>/dev/null || true   # test-only stand-in for macOS ~/Library

echo "== multi-device iCloud CRDT sync (root commit SHA + issue_id collision + doc sync)"
SYNC_HUB="$STUB/icloud-sync"
MAC_A="$STUB/mac-a/alpha-app"
MAC_B="$STUB/mac-b/renamed-app"
mkdir -p "$MAC_A"
git -C "$MAC_A" init -q
git -C "$MAC_A" -c user.name=t -c user.email=t@t commit -qm "initial root commit" --allow-empty
git clone -q "$MAC_A" "$MAC_B" 2>/dev/null
mkdir -p "$MAC_A/.projectmem" "$MAC_B/.projectmem"
printf '[project]\nname = "alpha-app"\n' > "$MAC_A/.projectmem/config.toml"
printf '[project]\nname = "renamed-app"\n' > "$MAC_B/.projectmem/config.toml"
printf '{"id":"evt_a1","type":"issue","issue_id":"0001","summary":"Crash on startup","timestamp":"2026-10-30T01:00:00Z"}\n' > "$MAC_A/.projectmem/events.jsonl"
printf '# Project Map\n\n## Project purpose\nReal architecture map from Mac A.\n' > "$MAC_A/.projectmem/PROJECT_MAP.md"
printf '{"id":"evt_b1","type":"issue","issue_id":"0001","summary":"Offline bug on Mac B","timestamp":"2026-10-30T02:00:00Z"}\n{"id":"evt_b2","type":"fix","issue_id":"0001","summary":"Fixed offline bug on Mac B","timestamp":"2026-10-30T02:05:00Z"}\n' > "$MAC_B/.projectmem/events.jsonl"
printf '0001' > "$MAC_B/.projectmem/.current_issue"
printf '# Project Map\n\n> Replace this placeholder with real project knowledge.\n' > "$MAC_B/.projectmem/PROJECT_MAP.md"
# Asymmetric multi-hop sync: both push while unaware, then mac-a merges first, then mac-b merges
mkdir -p "$SYNC_HUB/projects/root-$(git -C "$MAC_A" rev-list --max-parents=0 HEAD | cut -c1-12)/nodes"
cp "$MAC_B/.projectmem/events.jsonl" "$SYNC_HUB/projects/root-$(git -C "$MAC_A" rev-list --max-parents=0 HEAD | cut -c1-12)/nodes/mac-b.jsonl"
DEVGUARD_SYNC_DIR="$SYNC_HUB" DEVGUARD_DEVICE_ID="mac-a" /usr/bin/python3 -B "$KIT/bin/pjm_sync.py" --quiet "$MAC_A"
DEVGUARD_SYNC_DIR="$SYNC_HUB" DEVGUARD_DEVICE_ID="mac-b" /usr/bin/python3 -B "$KIT/bin/pjm_sync.py" --quiet "$MAC_B"
DEVGUARD_SYNC_DIR="$SYNC_HUB" DEVGUARD_DEVICE_ID="mac-a" /usr/bin/python3 -B "$KIT/bin/pjm_sync.py" --quiet "$MAC_A"
ROOT_SHA12=$(git -C "$MAC_A" rev-list --max-parents=0 HEAD | cut -c1-12)
check "different folder names map to same root-<sha12> bucket" '[ -f "$SYNC_HUB/projects/root-$ROOT_SHA12/nodes/mac-a.jsonl" ] && [ -f "$SYNC_HUB/projects/root-$ROOT_SHA12/nodes/mac-b.jsonl" ]'
check "offline issue_id 0001 collision resolved to 0001 + 0002 on both machines" '[ "$(wc -l < "$MAC_A/.projectmem/events.jsonl" | tr -d " ")" = 3 ] && cmp -s "$MAC_A/.projectmem/events.jsonl" "$MAC_B/.projectmem/events.jsonl" && grep -q "\"issue_id\": \"0002\", \"summary\": \"Fixed offline bug on Mac B\"" "$MAC_A/.projectmem/events.jsonl"'
check "active .current_issue marker updated when local issue_id renumbered" '[ "$(cat "$MAC_B/.projectmem/.current_issue")" = "0002" ]'
check "real PROJECT_MAP.md synced over placeholder without data loss" 'grep -q "Real architecture map from Mac A" "$MAC_B/.projectmem/PROJECT_MAP.md"'

RACE_REPO="$STUB/race-repo"
mkdir -p "$RACE_REPO/.projectmem"
git -C "$RACE_REPO" init -q
git -C "$RACE_REPO" -c user.name=t -c user.email=t@t commit -qm init --allow-empty
printf '[project]\nname = "race"\n' > "$RACE_REPO/.projectmem/config.toml"
: > "$RACE_REPO/.projectmem/events.jsonl"
race_out=$(DEVGUARD_SYNC_DIR="$STUB/race-hub" DEVGUARD_DEVICE_ID=mac-a /usr/bin/python3 -B "$KIT/tests/sync_race.py" "$KIT" "$RACE_REPO" 2>&1); code=$?
echo "  $race_out"
check "appends made during a sync rewrite are kept, without duplicates" '[ $code = 0 ]'
for case in slow-writer hook-lock remap-rescue; do
  lock_out=$(DEVGUARD_SYNC_DIR="$STUB/lock-hub-$case" DEVGUARD_DEVICE_ID=mac-a \
    /usr/bin/python3 -B "$KIT/tests/sync_lock.py" "$KIT" "$STUB/lock-$case" "$case" 2>&1); code=$?
  echo "  $case: $(printf '%s' "$lock_out" | tail -1)"
  check "sync $case" '[ $code = 0 ]'
done
rm -rf "$HOME/.agent-kit/locks"; rmdir "$HOME/.agent-kit" 2>/dev/null || true

echo "== helpers: run() exit code, project_ready in a git worktree"
( . "$KIT/lib.sh"; . "$KIT/components/common.sh"; DRY_RUN=0; run sh -c 'exit 3' ) > /dev/null 2>&1; code=$?
check "run() propagates a failing command's exit code" '[ $code = 3 ]'
WT_HOME="$STUB/wt-home"; WT_MAIN="$STUB/wt-main"; WT="$STUB/wt-linked"
mkdir -p "$WT_HOME/.projectmem" "$WT_MAIN"
git -C "$WT_MAIN" init -q
git -C "$WT_MAIN" -c user.name=t -c user.email=t@t commit -qm init --allow-empty
git -C "$WT_MAIN" worktree add -q "$WT" 2>/dev/null
printf '#!/bin/sh\npjm hooks post-commit\n' > "$WT_MAIN/.git/hooks/post-commit"
mkdir -p "$WT/.projectmem"; printf '[project]\n' > "$WT/.projectmem/config.toml"
printf '{"projects":{"x":{"path":"%s"}}}\n' "$WT" > "$WT_HOME/.projectmem/projects.json"
(cd "$WT" && unset STUB_LOG && HOME="$WT_HOME" && . "$KIT/lib.sh" && . "$KIT/components/common.sh" &&
  . "$KIT/components/projectmem.sh" && projectmem_project_ready); code=$?
check "projectmem_project_ready accepts a linked git worktree" '[ $code = 0 ]'

rm -rf "$HOME/.agent-kit-backup"
check ".claude.json byte-identical to original" 'cmp -s "$CJ" "$HOME.orig/.claude.json"'
check "whole HOME restored" 'same_tree "$HOME" "$HOME.orig"'
exit $fail
