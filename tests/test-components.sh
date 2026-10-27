#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2155,SC2034,SC2329
# SC2016: check() bodies are eval'd later, so single quotes are intended.
# Component install/wire/unwire/purge against a throwaway HOME with stub npm, python3, node and
# codegraph on PATH. Nothing is downloaded and your real home directory is never touched.
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd -P)
export HOME=$(mktemp -d)
STUB=$(mktemp -d)
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
  "install -g @colbymchenry/codegraph@"*) cp "$d/codegraph.real" "$d/codegraph"; chmod +x "$d/codegraph" ;;
  "install -g context-mode@"*) printf '#!/bin/sh\n' > "$d/context-mode"; chmod +x "$d/context-mode" ;;
  "uninstall -g @colbymchenry/codegraph") rm -f "$d/codegraph" ;;
  "uninstall -g context-mode") rm -f "$d/context-mode" ;;
esac
EOF
# Fake codegraph: writes/removes its MCP entry the way the real installer does.
cat > "$STUB/bin/codegraph.real" <<'EOF'
#!/bin/sh
echo "codegraph $*" >> "$STUB_LOG"
put() { f=$1; k=$2; mkdir -p "$(dirname "$f")"; [ -f "$f" ] || echo '{}' > "$f"
        jq --arg k "$k" '.[$k].codegraph = {"command":"codegraph","args":["serve","--mcp"]}' "$f" > "$f.t" && mv "$f.t" "$f"; }
del() { f=$1; k=$2; [ -f "$f" ] || return 0
        jq --arg k "$k" 'del(.[$k].codegraph) | if .[$k] == {} then del(.[$k]) else . end' "$f" > "$f.t" && mv "$f.t" "$f"
        [ "$(jq -c . "$f")" = "{}" ] && rm -f "$f"; return 0; }
VS="$HOME/.config/Code/User/mcp.json"; [ "$(uname -s)" = Darwin ] && VS="$HOME/Library/Application Support/Code/User/mcp.json"
case "$1" in
  install) case "$2" in
             --target=claude) put "$HOME/.claude.json" mcpServers ;;
             --target=copilot-vscode) put "$VS" servers ;;
             --target=antigravity) put "$HOME/.gemini/antigravity/mcp_config.json" mcpServers ;;
           esac ;;
  uninstall) del "$HOME/.claude.json" mcpServers; del "$VS" servers; del "$HOME/.gemini/antigravity/mcp_config.json" mcpServers ;;
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
chmod +x "$STUB/bin/npm" "$STUB/bin/python3" "$STUB/bin/node"

# ---- seed user content -------------------------------------------------------------------------
echo '{"numStartups":7,"mcpServers":{"mine":{"command":"my-server"}}}' | jq . > "$HOME/.claude.json"
mkdir -p "$HOME/.claude"
cp -R "$HOME" "$HOME.orig"
CJ="$HOME/.claude.json"
AG="$HOME/.gemini/antigravity/mcp_config.json"
VS="$HOME/.config/Code/User/mcp.json"; [ "$(uname -s)" = Darwin ] && VS="$HOME/Library/Application Support/Code/User/mcp.json"
has() { jq -e --arg k "$2" --arg n "$3" '.[$k] | has($n)' "$1" >/dev/null 2>&1; }

echo "== unknown component"
"$KIT/install.sh" --with=bogus >/dev/null 2>&1; code=$?
check "unknown component rejected (64)" '[ $code = 64 ]'

echo "== dry-run with components"
"$KIT/install.sh" --dry-run --with=codegraph,projectmem,context-mode > /dev/null 2>&1
check "dry-run changes nothing" 'same_tree "$HOME" "$HOME.orig"'
check "dry-run calls no installer" '[ ! -s "$STUB_LOG" ]'

echo "== install codegraph,projectmem,context-mode"
"$KIT/install.sh" --with=codegraph,projectmem,context-mode > "$STUB/install1.log" 2>&1; code=$?
check "install exit 0" '[ $code = 0 ]'
check "codegraph installed via pinned npm" '[ "$(calls "npm install -g @colbymchenry/codegraph@")" = 1 ]'
check "projectmem venv created" '[ -x "$HOME/.local/share/agent-kit/projectmem-venv/bin/pjm" ]'
check "pjm linked on PATH" '[ -L "$HOME/.local/bin/pjm" ]'
for a in "$CJ:mcpServers" "$VS:servers" "$AG:mcpServers"; do
  f=${a%:*}; k=${a##*:}
  for n in codegraph projectmem context-mode; do
    check "$n wired in $(basename "$f")" 'has "$f" "$k" "$n"'
  done
done
check "projectmem points at venv python" '[ "$(jq -r ".mcpServers.projectmem.command" "$CJ")" = "$HOME/.local/share/agent-kit/projectmem-venv/bin/python" ]'
check "user MCP server kept" 'has "$CJ" mcpServers mine'
check "unrelated .claude.json key kept" '[ "$(jq .numStartups "$CJ")" = 7 ]'
check "state recorded" '[ -f "$HOME/.agent-kit/components/projectmem/installed-by-kit" ] && grep -qx antigravity "$HOME/.agent-kit/components/codegraph/wired"'

echo "== re-install"
cp "$STUB_LOG" "$STUB/before"; snap "$HOME" > "$STUB/snap1"
"$KIT/install.sh" --with=codegraph,projectmem,context-mode > /dev/null 2>&1
check "no reinstall of present CLIs" '! diff "$STUB/before" "$STUB_LOG" | grep -q "npm install\|venv"'
check "re-install leaves files identical" '[ "$(snap "$HOME")" = "$(cat "$STUB/snap1")" ]'

echo "== status"
"$KIT/status.sh" > "$STUB/status.log" 2>&1
check "status lists wired components" 'grep -q "projectmem: CLI installed, managed by agent-kit" "$STUB/status.log"'

echo "== agent-kit-project init"
repo=$(mktemp -d); (cd "$repo" && git init -q && printf 'build/' > .gitignore && agent-kit-project init > "$STUB/proj.log" 2>&1); code=$?
check "project init exit 0" '[ $code = 0 ]'
check "codegraph index created" '[ -d "$repo/.codegraph" ]'
check "projectmem initialized" '[ -d "$repo/.projectmem" ]'
check ".verify/ added on its own line" '[ "$(cat "$repo/.gitignore")" = "$(printf "build/\n.verify/")" ]'
(cd "$repo" && agent-kit-project init > /dev/null 2>&1)
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
"$KIT/install.sh" --with=codegraph,projectmem,context-mode > /dev/null 2>&1
check "reinstall did not reinstall CLIs" '[ "$(calls "npm install -g @colbymchenry/codegraph@")" = 1 ]'
"$KIT/uninstall.sh" --purge > "$STUB/un2.log" 2>&1
check "kit-installed codegraph removed on purge" '[ ! -e "$STUB/bin/codegraph" ] && [ "$(calls "npm uninstall -g @colbymchenry/codegraph")" = 1 ]'
check "kit-installed context-mode removed on purge" '[ ! -e "$STUB/bin/context-mode" ]'
check "kit-installed projectmem venv removed on purge" '[ ! -e "$HOME/.local/share/agent-kit" ] && [ ! -e "$HOME/.local/bin/pjm" ]'
check "all state gone after purge" '[ ! -e "$HOME/.agent-kit" ]'

echo "== user-installed CLI survives purge"
cp "$STUB/bin/codegraph.real" "$STUB/bin/codegraph"
"$KIT/install.sh" --with=codegraph > /dev/null 2>&1
"$KIT/uninstall.sh" --purge > "$STUB/un3.log" 2>&1
check "user codegraph kept on purge" '[ -x "$STUB/bin/codegraph" ] && grep -q "kept       codegraph CLI (not installed" "$STUB/un3.log"'
check "but its wiring removed" '! has "$CJ" mcpServers codegraph'

rm -rf "$HOME/.agent-kit-backup"
check ".claude.json byte-identical to original" 'cmp -s "$CJ" "$HOME.orig/.claude.json"'
check "whole HOME restored" 'same_tree "$HOME" "$HOME.orig"'
exit $fail
