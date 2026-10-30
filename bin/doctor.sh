#!/usr/bin/env bash
# devguard doctor: audit and optionally repair common installation, wiring, and plugin conflicts.
#
#   devguard doctor          run all 7 health checks (read-only; exits 1 if issues found)
#   devguard doctor --fix    automatically repair all detected issues and back up changed files
set -u

KIT_DIR=$(cd "$(dirname "$0")/.." && pwd -P)
DRY_RUN=0
FIX=0

for arg in "$@"; do
  case "$arg" in
    --fix) FIX=1 ;;
    -h | --help)
      cat <<EOF
Usage: devguard doctor [--fix]

Checks 7 common failure modes:
  1. Legacy tokless residue (binaries, share dir, broken .zshrc block)
  2. Broken or conflicting symlinks in ~/.local/bin
  3. Conflicting brevity/workflow plugins (caveman, ponytail, cavecrew)
  4. MCP server configuration & canonical file placement
  5. RTK global plugin & telemetry health
  6. Core rules block synchronization against rules/core.md
  7. Component version drift against pinned versions

Options:
  --fix    Automatically repair all detected issues (backs up modified files to ~/.agent-kit-backup/)
EOF
      exit 0
      ;;
  esac
done

if [ "$FIX" = 1 ]; then
  BACKUP_DIR="$HOME/.agent-kit-backup/doctor-$(date +%Y%m%d-%H%M%S)"
else
  BACKUP_DIR=""
fi

# shellcheck source=lib.sh
. "$KIT_DIR/lib.sh"
# shellcheck source=components/common.sh
. "$KIT_DIR/components/common.sh"
load_components

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_OK=$'\033[32m' C_WARN=$'\033[33m' C_BOLD=$'\033[1m' C_RESET=$'\033[0m'
else
  C_OK="" C_WARN="" C_BOLD="" C_RESET=""
fi

issues=0
fixed=0

ok() { echo "  ${C_OK}✓ ok${C_RESET}     $1"; }
issue() {
  issues=$((issues + 1))
  echo "  ${C_WARN}! warn${C_RESET}   $1"
}
repaired() {
  fixed=$((fixed + 1))
  echo "  ${C_OK}✓ fixed${C_RESET}  $1"
}

echo "${C_BOLD}╭─ devguard doctor ──────────────────────────────────────────────────────────────╮${C_RESET}"

# ---- 1. Legacy tokless residue -----------------------------------------------------------------
tokless_found=0
if [ -e "$HOME/.local/bin/tokless" ] || [ -L "$HOME/.local/bin/tokless" ] ||
   { [ -f "$HOME/.local/bin/rtk" ] && [ ! -L "$HOME/.local/bin/rtk" ]; } ||
   [ -d "$HOME/.local/share/tokless" ] ||
   [ -f "$HOME/.config/opencode/plugins/tokless-rtk.ts" ] ||
   { [ -f "$ZSHRC" ] && grep -q "tokless" "$ZSHRC" 2>/dev/null; } ||
   { [ -f "$CLAUDE_SETTINGS" ] && command -v jq >/dev/null 2>&1 && jq -e '.env.ANTHROPIC_BASE_URL // "" | test("127\\.0\\.0\\.1|localhost")' "$CLAUDE_SETTINGS" >/dev/null 2>&1; }; then
  tokless_found=1
fi

if [ "$tokless_found" = 0 ]; then
  ok "1. No legacy tokless residue"
else
  if [ "$FIX" = 1 ]; then
    if [ -x "$HOME/.local/bin/tokless" ]; then
      "$HOME/.local/bin/tokless" proxy stop >/dev/null 2>&1 || true
      "$HOME/.local/bin/tokless" disable --agents claude,opencode,antigravity >/dev/null 2>&1 ||
        "$HOME/.local/bin/tokless" disable >/dev/null 2>&1 || true
    fi
    rm -f "$HOME/.local/bin/tokless" "$HOME/.config/opencode/plugins/tokless-rtk.ts"
    if [ -f "$HOME/.local/bin/rtk" ] && [ ! -L "$HOME/.local/bin/rtk" ]; then
      mkdir -p "$BACKUP_DIR"
      mv "$HOME/.local/bin/rtk" "$BACKUP_DIR/tokless-rtk"
      command -v rtk >/dev/null 2>&1 || rtk_install >/dev/null 2>&1 || true
    fi
    if [ -d "$HOME/.local/share/tokless" ]; then
      mkdir -p "$BACKUP_DIR"
      mv "$HOME/.local/share/tokless" "$BACKUP_DIR/tokless-share"
    fi
    if [ -f "$CLAUDE_SETTINGS" ] && command -v jq >/dev/null 2>&1 &&
       jq -e '.env.ANTHROPIC_BASE_URL // "" | test("127\\.0\\.0\\.1|localhost")' "$CLAUDE_SETTINGS" >/dev/null 2>&1; then
      backup "$CLAUDE_SETTINGS"
      tmp=$(mktemp)
      jq 'if .env then del(.env.ANTHROPIC_BASE_URL) | if .env == {} then del(.env) else . end else . end' "$CLAUDE_SETTINGS" > "$tmp" && cat "$tmp" > "$CLAUDE_SETTINGS"
      rm -f "$tmp"
    fi
    if [ -f "$ZSHRC" ] && grep -q "tokless" "$ZSHRC" 2>/dev/null; then
      backup "$ZSHRC"
      tmp=$(mktemp)
      awk '/^# >>> tokless/{s=1;next} /^# <<< tokless/{s=0;next} /^# tokless$/{next} !s' "$ZSHRC" > "$tmp"
      cat "$tmp" > "$ZSHRC"
      rm -f "$tmp"
    fi
    repaired "1. Stopped/disabled legacy tokless and cleaned residue"
  else
    issue "1. Legacy tokless residue found (~/.local/bin/tokless, proxy env, ~/.local/share/tokless, or ~/.zshrc)"
  fi
fi

# ---- 2. Symlinks in ~/.local/bin ---------------------------------------------------------------
bad_links=""
if [ -d "$HOME/.local/bin" ]; then
  for f in "$HOME/.local/bin"/*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    if [ -L "$f" ] && [ ! -e "$f" ]; then
      bad_links="$bad_links $(basename "$f")(broken)"
    fi
  done
fi
if [ -L "$HOME/.local/bin/pjm-mcp" ]; then
  bad_links="$bad_links pjm-mcp(legacy-uv)"
fi
for old_link in $LEGACY_LINKS; do
  if [ -L "$old_link" ]; then
    bad_links="$bad_links $(basename "$old_link")(legacy-name)"
  fi
done
if [ -x "$PROJECTMEM_VENV/bin/pjm" ]; then
  for b in pjm projectmem; do
    if [ ! -L "$HOME/.local/bin/$b" ] || [ "$(readlink "$HOME/.local/bin/$b")" != "$PROJECTMEM_VENV/bin/$b" ]; then
      bad_links="$bad_links $b(wrong-target)"
    fi
  done
fi

if [ -z "$bad_links" ]; then
  ok "2. ~/.local/bin symlinks healthy"
else
  if [ "$FIX" = 1 ]; then
    if [ -d "$HOME/.local/bin" ]; then
      for f in "$HOME/.local/bin"/*; do
        [ -L "$f" ] && [ ! -e "$f" ] && rm -f "$f"
      done
    fi
    rm -f "$HOME/.local/bin/pjm-mcp"
    for old_link in $LEGACY_LINKS; do
      [ -L "$old_link" ] && rm -f "$old_link"
    done
    if [ -x "$PROJECTMEM_VENV/bin/pjm" ]; then
      mkdir -p "$HOME/.local/bin"
      for b in pjm projectmem; do
        ln -sfn "$PROJECTMEM_VENV/bin/$b" "$HOME/.local/bin/$b"
      done
    fi
    repaired "2. Repaired ~/.local/bin symlinks ($bad_links )"
  else
    issue "2. Broken or stale symlinks in ~/.local/bin:$bad_links"
  fi
fi

# ---- 3. Conflicting brevity/workflow plugins ---------------------------------------------------
plugin_conflicts=""
if [ -f "$CLAUDE_SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  c_plugs=$(jq -r '((.enabledPlugins // {}) + (.extraKnownMarketplaces // {})) | keys[] | select(test("^(caveman|ponytail|cavecrew)"))' "$CLAUDE_SETTINGS" 2>/dev/null | tr '\n' ' ')
  [ -n "$c_plugs" ] && plugin_conflicts="$plugin_conflicts claude($c_plugs)"
fi
for cf in "$HOME/.claude"/.caveman* "$HOME/.claude"/.ponytail*; do
  [ -e "$cf" ] || [ -L "$cf" ] || continue
  plugin_conflicts="$plugin_conflicts claude-flags"
  break
done
if [ -f "$OPENCODE_MCP" ] && command -v jq >/dev/null 2>&1; then
  oc_plugs=$(jq -r '(.plugin // [])[] | select(test("caveman|ponytail|cavecrew|tokless"))' "$OPENCODE_MCP" 2>/dev/null | tr '\n' ' ')
  [ -n "$oc_plugs" ] && plugin_conflicts="$plugin_conflicts opencode.jsonc($oc_plugs)"
fi
for d in "$HOME/.gemini/config/skills" "$HOME/.gemini/config/plugins" "$HOME/.config/opencode/plugins" "$HOME/.config/opencode/skills"; do
  [ -d "$d" ] || continue
  for p in "$d"/caveman* "$d"/ponytail* "$d"/cavecrew* "$d"/tokless*; do
    [ -e "$p" ] || [ -L "$p" ] || continue
    plugin_conflicts="$plugin_conflicts $(basename "$p")"
  done
done

if [ -z "$plugin_conflicts" ]; then
  ok "3. No conflicting plugins (caveman, ponytail, cavecrew)"
else
  if [ "$FIX" = 1 ]; then
    if [ -f "$CLAUDE_SETTINGS" ] && command -v jq >/dev/null 2>&1; then
      backup "$CLAUDE_SETTINGS"
      tmp=$(mktemp)
      jq '
        if .enabledPlugins then .enabledPlugins |= with_entries(select(.key | test("^(caveman|ponytail|cavecrew)") | not)) | if .enabledPlugins == {} then del(.enabledPlugins) else . end else . end
        | if .extraKnownMarketplaces then .extraKnownMarketplaces |= with_entries(select(.key | test("^(caveman|ponytail|cavecrew)") | not)) | if .extraKnownMarketplaces == {} then del(.extraKnownMarketplaces) else . end else . end
      ' "$CLAUDE_SETTINGS" > "$tmp" && cat "$tmp" > "$CLAUDE_SETTINGS"
      rm -f "$tmp"
    fi
    for cf in "$HOME/.claude"/.caveman* "$HOME/.claude"/.ponytail*; do
      [ -e "$cf" ] || [ -L "$cf" ] || continue
      backup "$cf"
      rm -f "$cf"
    done
    if [ -f "$OPENCODE_MCP" ] && command -v jq >/dev/null 2>&1 &&
       jq -e '(.plugin // []) | any(test("caveman|ponytail|cavecrew|tokless"))' "$OPENCODE_MCP" >/dev/null 2>&1; then
      backup "$OPENCODE_MCP"
      tmp=$(mktemp)
      jq 'if .plugin then .plugin |= map(select(test("caveman|ponytail|cavecrew|tokless") | not)) | if .plugin == [] then del(.plugin) else . end else . end' "$OPENCODE_MCP" > "$tmp" && cat "$tmp" > "$OPENCODE_MCP"
      rm -f "$tmp"
    fi
    for d in "$HOME/.gemini/config/skills" "$HOME/.gemini/config/plugins" "$HOME/.config/opencode/plugins" "$HOME/.config/opencode/skills"; do
      [ -d "$d" ] || continue
      for p in "$d"/caveman* "$d"/ponytail* "$d"/cavecrew* "$d"/tokless*; do
        [ -e "$p" ] || [ -L "$p" ] || continue
        mkdir -p "$BACKUP_DIR/plugins"
        mv "$p" "$BACKUP_DIR/plugins/$(basename "$d")-$(basename "$p")"
      done
    done
    repaired "3. Removed conflicting plugins ($plugin_conflicts )"
  else
    issue "3. Conflicting plugins active:$plugin_conflicts"
  fi
fi

# ---- 4. MCP config & canonical file placement --------------------------------------------------
mcp_issues=""
LEGACY_AG_MCP="$HOME/.gemini/antigravity/mcp_config.json"
if [ -f "$LEGACY_AG_MCP" ] && command -v jq >/dev/null 2>&1; then
  for c in codegraph projectmem context-mode; do
    if jq -e --arg n "$c" '.mcpServers | has($n)' "$LEGACY_AG_MCP" >/dev/null 2>&1; then
      mcp_issues="$mcp_issues legacy-antigravity($c)"
    fi
  done
fi
for c in codegraph projectmem context-mode; do
  [ -d "$(state_dir "$c")" ] || continue
  for a in $(state_wired "$c"); do
    f=$(agent_mcp_file "$a")
    if [ ! -f "$f" ] || ! mcp_has "$a" "$c" || { [ "$a" = antigravity ] && ! jq -e --arg n "$c" '.mcpServers | has($n)' "$f" >/dev/null 2>&1; }; then
      mcp_issues="$mcp_issues $a:$c(missing-in-$(basename "$f"))"
    fi
  done
done

if [ -z "$mcp_issues" ]; then
  ok "4. MCP configurations in canonical paths"
else
  if [ "$FIX" = 1 ]; then
    if [ -f "$LEGACY_AG_MCP" ] && command -v jq >/dev/null 2>&1; then
      backup "$LEGACY_AG_MCP"
      tmp=$(mktemp)
      jq 'if .mcpServers then del(.mcpServers.codegraph, .mcpServers.projectmem, .mcpServers."context-mode") | if .mcpServers == {} then del(.mcpServers) else . end else . end' "$LEGACY_AG_MCP" > "$tmp"
      if [ "$(jq -c . "$tmp")" = "{}" ]; then
        rm -f "$LEGACY_AG_MCP"
        rmdir "$HOME/.gemini/antigravity" 2>/dev/null || true
      else
        cat "$tmp" > "$LEGACY_AG_MCP"
      fi
      rm -f "$tmp"
    fi
    for c in codegraph projectmem context-mode; do
      [ -d "$(state_dir "$c")" ] || continue
      for a in $(state_wired "$c"); do
        "$(fn_name "$c")_wire" "$a" >/dev/null 2>&1 || true
      done
    done
    repaired "4. Synced MCP entries to canonical files ($mcp_issues )"
  else
    issue "4. MCP configuration drift:$mcp_issues"
  fi
fi

# ---- 5. RTK Antigravity global plugin & telemetry ----------------------------------------------
rtk_issues=""
if [ -d "$(state_dir rtk)" ] && grep -qxF "antigravity" "$(state_dir rtk)/wired" 2>/dev/null; then
  if [ ! -f "$HOME/.gemini/config/plugins/rtk/plugin.json" ] ||
     [ ! -f "$HOME/.gemini/config/plugins/rtk/hooks.json" ] ||
     [ ! -f "$HOME/.gemini/config/plugins/rtk/rules/AGENTS.md" ]; then
    rtk_issues="antigravity-plugin-incomplete"
  fi
fi

if [ -z "$rtk_issues" ]; then
  ok "5. RTK global plugin and hooks healthy"
else
  if [ "$FIX" = 1 ]; then
    rtk_wire antigravity >/dev/null 2>&1 || true
    repaired "5. Re-installed RTK global plugin for Antigravity"
  else
    issue "5. RTK Antigravity global plugin missing (~/.gemini/config/plugins/rtk)"
  fi
fi

# ---- 6. Core rules block synchronization -------------------------------------------------------
rules_drift=""
expected_rules=$(cat "$KIT_DIR/rules/core.md")
for rf in "$CLAUDE_RULES" "$VSCODE_RULES" "$AG_RULES" "$OPENCODE_RULES" "$CURSOR_RULES" "$CODEX_RULES"; do
  if has_block "$rf"; then
    actual_rules=$(awk -v b="$BEGIN_MARK" -v e="$END_MARK" '$0==b{s=1;next} $0==e{s=0;next} s' "$rf")
    if [ "$actual_rules" != "$expected_rules" ]; then
      rules_drift="$rules_drift $(basename "$rf")"
    fi
  fi
done
for old_cr in $LEGACY_CURSOR_RULES; do
  if has_block "$old_cr"; then
    rules_drift="$rules_drift $(basename "$old_cr")(legacy-cursor-rule)"
  fi
done

if [ -z "$rules_drift" ]; then
  ok "6. Core rules blocks match rules/core.md"
else
  if [ "$FIX" = 1 ]; then
    for rf in "$CLAUDE_RULES" "$VSCODE_RULES" "$AG_RULES" "$OPENCODE_RULES" "$CURSOR_RULES" "$CODEX_RULES"; do
      has_block "$rf" && set_block "$rf" "$KIT_DIR/rules/core.md" >/dev/null
    done
    for old_cr in $LEGACY_CURSOR_RULES; do
      has_block "$old_cr" && remove_block "$old_cr" >/dev/null
    done
    repaired "6. Updated core rules blocks ($rules_drift )"
  else
    issue "6. Outdated core rules block in:$rules_drift"
  fi
fi

# ---- 7. Component & companion CLI versions -----------------------------------------------------
ver_drift=""
for c in $ALL_COMPONENTS; do
  f=$(fn_name "$c")
  "${f}_present" || continue
  if type "${f}_pinned_version" >/dev/null 2>&1 && type "${f}_installed_version" >/dev/null 2>&1; then
    pinned=$("${f}_pinned_version")
    inst=$("${f}_installed_version")
    if [ -n "$pinned" ] && [ -n "$inst" ] && [ "$inst" != "$pinned" ]; then
      ver_drift="$ver_drift $c($inst->$pinned)"
    fi
  fi
done
if [ -z "${STUB_LOG:-}" ] && command -v brew >/dev/null 2>&1; then
  command -v ast-grep >/dev/null 2>&1 || ver_drift="$ver_drift ast-grep(missing)"
  command -v xcbeautify >/dev/null 2>&1 || ver_drift="$ver_drift xcbeautify(missing)"
fi

if [ -z "$ver_drift" ]; then
  ok "7. Component & companion CLI versions healthy (codegraph, projectmem, rtk, ast-grep, xcbeautify)"
else
  if [ "$FIX" = 1 ]; then
    for c in $ALL_COMPONENTS; do
      component_upgrade "$c" >/dev/null 2>&1 || true
    done
    if [ -z "${STUB_LOG:-}" ] && command -v brew >/dev/null 2>&1; then
      command -v ast-grep >/dev/null 2>&1 || brew install ast-grep >/dev/null 2>&1 || true
      command -v xcbeautify >/dev/null 2>&1 || brew install xcbeautify >/dev/null 2>&1 || true
    fi
    repaired "7. Upgraded/installed component & companion CLIs ($ver_drift )"
  else
    issue "7. Component or companion CLI drift:$ver_drift"
  fi
fi

echo "${C_BOLD}╰────────────────────────────────────────────────────────────────────────────────╯${C_RESET}"
if [ "$FIX" = 1 ]; then
  [ -d "${BACKUP_DIR:-}" ] && { echo "Backups: $BACKUP_DIR"; prune_backups; }
  echo "Doctor complete: $fixed repaired."
  exit 0
elif [ "$issues" -gt 0 ]; then
  echo "Found $issues issue(s). Run 'devguard doctor --fix' to repair automatically."
  exit 1
else
  echo "Everything looks healthy (0 issues)."
  exit 0
fi
