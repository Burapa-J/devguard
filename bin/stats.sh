#!/usr/bin/env bash
# agent-kit stats: unified token savings & index statistics across rtk, projectmem and codegraph.
#
#   agent-kit stats                 compact summary across all tools and projects
#   agent-kit stats --daily | -d    include daily rtk breakdown
#   agent-kit stats --project | -p  current project only
#   agent-kit stats --reset         reset rtk token counter (with confirmation, or --yes)
#   agent-kit stats --dashboard     generate and open the projectmem HTML dashboard
set -u

KIT_DIR=$(cd "$(dirname "$0")/.." && pwd -P)
# shellcheck source=lib.sh
. "$KIT_DIR/lib.sh"
# shellcheck source=components/common.sh
. "$KIT_DIR/components/common.sh"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_OK=$'\033[32m' C_OFF=$'\033[90m' C_BOLD=$'\033[1m' C_CYAN=$'\033[36m' C_RESET=$'\033[0m'
else
  C_OK="" C_OFF="" C_BOLD="" C_CYAN="" C_RESET=""
fi

MODE="summary"
YES=0
for arg in "$@"; do
  case "$arg" in
    -d | --daily) MODE="daily" ;;
    -p | --project) MODE="project" ;;
    --reset) MODE="reset" ;;
    -y | --yes) YES=1 ;;
    --dashboard) MODE="dashboard" ;;
    -h | --help)
      cat <<EOF
Usage: agent-kit stats [options]

  (no options)        Unified summary of rtk, projectmem and codegraph stats
  -d, --daily         Show daily rtk token savings breakdown
  -p, --project       Show stats for the current git repository only
  --dashboard         Generate and open the projectmem HTML dashboard
  --reset [--yes]     Reset rtk token savings counter to zero
EOF
      exit 0
      ;;
  esac
done

if [ "$MODE" = "reset" ]; then
  if ! command -v rtk >/dev/null 2>&1; then
    echo "rtk is not installed."
    exit 1
  fi
  if [ "$YES" = 1 ]; then
    rtk gain --reset --yes
  else
    rtk gain --reset
  fi
  exit $?
fi

if [ "$MODE" = "dashboard" ]; then
  if ! command -v pjm >/dev/null 2>&1; then
    echo "projectmem (pjm) is not installed."
    exit 1
  fi
  pjm dashboard
  if [ -f "$HOME/.projectmem/dashboard/index.html" ] && command -v open >/dev/null 2>&1; then
    open "$HOME/.projectmem/dashboard/index.html"
  fi
  exit 0
fi

if [ "$MODE" = "project" ]; then
  echo "${C_BOLD}╭─ Project Statistics ($PWD) ────────────────────────────────────╮${C_RESET}"
  echo "${C_BOLD}╰────────────────────────────────────────────────────────────────╯${C_RESET}"
  if command -v rtk >/dev/null 2>&1; then
    echo "${C_CYAN}▸ RTK (current project)${C_RESET}"
    rtk gain -p --text 2>/dev/null || rtk gain -p 2>/dev/null || true
    echo
  fi
  if command -v pjm >/dev/null 2>&1 && [ -d .projectmem ]; then
    echo "${C_CYAN}▸ ProjectMem (current project)${C_RESET}"
    pjm stats 2>/dev/null || true
    echo
  fi
  if command -v codegraph >/dev/null 2>&1 && [ -d .codegraph ]; then
    echo "${C_CYAN}▸ CodeGraph (current project)${C_RESET}"
    codegraph status . --no-color 2>/dev/null || true
  fi
  exit 0
fi

# ---- 1. RTK Token Savings ----------------------------------------------------------------------
echo "${C_BOLD}╭─ 1. RTK Shell Compression Savings ─────────────────────────────────────────────╮${C_RESET}"
if command -v rtk >/dev/null 2>&1; then
  if [ "$MODE" = "daily" ]; then
    rtk gain -d --text 2>/dev/null || rtk gain -d 2>/dev/null || true
  else
    rtk gain --text 2>/dev/null || rtk gain 2>/dev/null || true
  fi
else
  echo "  ${C_OFF}rtk is not installed.${C_RESET}"
fi
echo "${C_BOLD}╰────────────────────────────────────────────────────────────────────────────────╯${C_RESET}"
echo

# ---- 2. ProjectMem + CodeGraph Per-Project Table -----------------------------------------------
echo "${C_BOLD}╭─ 2. Repositories (CodeGraph & ProjectMem) ─────────────────────────────────────╮${C_RESET}"
printf "${C_BOLD}│ %-28s %8s %8s %8s %8s %12s │${C_RESET}\n" \
  "Repository" "Files" "Symbols" "Edges" "Fixes" "Tokens Saved"
echo "├────────────────────────────────────────────────────────────────────────────────┤"

total_repos=0
total_files=0
total_nodes=0
total_edges=0
total_fixes=0
total_pjm_tokens=0

scan_roots=""
if [ -f "$AUTO_ROOTS" ]; then
  scan_roots=$(cat "$AUTO_ROOTS")
elif [ -d "$HOME/Developer" ]; then
  scan_roots="$HOME/Developer"
fi

repos_tmp=$(mktemp)
for root in $scan_roots; do
  [ -d "$root" ] || continue
  find "$root" -mindepth 2 -maxdepth 3 -name .git -not -path '*/node_modules/*' 2>/dev/null |
    while IFS= read -r g; do dirname "$g"; done
done | LC_ALL=C sort -u > "$repos_tmp"

while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  [ -d "$repo/.codegraph" ] || [ -d "$repo/.projectmem" ] || continue
  total_repos=$((total_repos + 1))
  name=$(basename "$repo")
  case "${#name}" in
    [3-9][0-9]) name="${name:0:25}..." ;;
  esac

  files="-" nodes="-" edges="-"
  if [ -d "$repo/.codegraph" ] && command -v codegraph >/dev/null 2>&1; then
    cg=$(codegraph status "$repo" --no-color 2>/dev/null || true)
    f_val=$(printf '%s\n' "$cg" | awk '/Files:/ {gsub(",","",$2); print $2; exit}')
    n_val=$(printf '%s\n' "$cg" | awk '/Nodes:/ {gsub(",","",$2); print $2; exit}')
    e_val=$(printf '%s\n' "$cg" | awk '/Edges:/ {gsub(",","",$2); print $2; exit}')
    [ -n "$f_val" ] && { files=$f_val; total_files=$((total_files + f_val)); }
    [ -n "$n_val" ] && { nodes=$n_val; total_nodes=$((total_nodes + n_val)); }
    [ -n "$e_val" ] && { edges=$e_val; total_edges=$((total_edges + e_val)); }
  fi

  fixes="-" pjm_tok="-"
  if [ -d "$repo/.projectmem" ] && command -v pjm >/dev/null 2>&1; then
    ps=$(cd "$repo" && pjm stats 2>/dev/null || true)
    fx_val=$(printf '%s\n' "$ps" | awk '/Fixes:/ {gsub(",","",$2); print $2; exit}')
    tk_val=$(printf '%s\n' "$ps" | awk '/Total Tokens Saved:/ {gsub(",","",$4); print $4; exit}')
    [ -n "$fx_val" ] && { fixes=$fx_val; total_fixes=$((total_fixes + fx_val)); }
    [ -n "$tk_val" ] && { pjm_tok=$tk_val; total_pjm_tokens=$((total_pjm_tokens + tk_val)); }
  fi

  printf "│ %-28s %8s %8s %8s %8s %12s │\n" "$name" "$files" "$nodes" "$edges" "$fixes" "$pjm_tok"
done < "$repos_tmp"
rm -f "$repos_tmp"

echo "├────────────────────────────────────────────────────────────────────────────────┤"
printf "${C_BOLD}│ %-28s %8s %8s %8s %8s %12s │${C_RESET}\n" \
  "TOTAL ($total_repos repos)" "$total_files" "$total_nodes" "$total_edges" "$total_fixes" "$total_pjm_tokens"
echo "${C_BOLD}╰────────────────────────────────────────────────────────────────────────────────╯${C_RESET}"
echo "${C_OFF}Tips: potless stats -d (รายวัน) · potless stats -p (โปรเจกต์นี้) · potless stats --reset (รีเซ็ตสถิติ rtk)${C_RESET}"
