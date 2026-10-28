#!/usr/bin/env bash
# Interactive TUI helpers (tokless-style multi-select & menu) for bash 3.2+.
# Used by `agent-kit` when connected to a terminal.

# ui_multiselect <title> <items_csv> <defaults_csv>
# Prints the selected items (comma-separated) into $UI_RESULT and returns 0 (or 1 on cancel).
ui_multiselect() {
  local title=$1 items_csv=$2 defaults_csv=$3
  local C_OK=$'\033[32m' C_CYAN=$'\033[36m' C_DIM=$'\033[90m' C_BOLD=$'\033[1m' C_RESET=$'\033[0m'
  local items=() labels=() selected=() i=0 n cur=0 key rest d

  old_ifs=$IFS; IFS=,
  for item in $items_csv; do
    IFS=$old_ifs
    items[$i]=${item%%:*}
    labels[$i]=${item#*:}
    selected[$i]=0
    case ",$defaults_csv," in *,"${items[$i]}",*) selected[$i]=1 ;; esac
    i=$((i + 1))
  done
  IFS=$old_ifs
  n=$i

  printf '\033[?25l' >&2
  trap 'printf "\033[?25h" >&2' INT TERM

  while true; do
    printf '\n%s* %s%s\n' "$C_BOLD" "$title" "$C_RESET" >&2
    i=0
    while [ $i -lt $n ]; do
      local ptr=" " box="( )" mark=" " col=$C_DIM
      [ $i -eq $cur ] && ptr="${C_CYAN}>${C_RESET}"
      if [ "${selected[$i]}" = 1 ]; then
        box="${C_OK}(x)${C_RESET}"
        mark="${C_OK}✓${C_RESET}"
        col=$C_BOLD
      fi
      printf '│   %s %s  %s %s%-36s%s\n' "$ptr" "$box" "$mark" "$col" "${labels[$i]}" "$C_RESET" >&2
      i=$((i + 1))
    done
    printf '  %s------------------------------------------------------------%s\n' "$C_DIM" "$C_RESET" >&2
    printf '  %s↑/↓ move · <space> toggle · <a> all · <enter> confirm · <q> cancel%s\n' "$C_DIM" "$C_RESET" >&2

    IFS= read -rsn1 key < /dev/tty || { printf '\033[?25h' >&2; return 1; }
    if [ "$key" = $'\x1b' ]; then
      IFS= read -rsn2 rest < /dev/tty || true
      case "$rest" in
        "[A") cur=$(( (cur - 1 + n) % n )) ;;
        "[B") cur=$(( (cur + 1) % n )) ;;
      esac
    elif [ "$key" = " " ]; then
      if [ "${selected[$cur]}" = 1 ]; then selected[$cur]=0; else selected[$cur]=1; fi
    elif [ "$key" = "a" ] || [ "$key" = "A" ]; then
      local all_on=1
      i=0; while [ $i -lt $n ]; do [ "${selected[$i]}" = 0 ] && all_on=0; i=$((i + 1)); done
      i=0; while [ $i -lt $n ]; do selected[$i]=$((1 - all_on)); i=$((i + 1)); done
    elif [ "$key" = "q" ] || [ "$key" = "Q" ]; then
      printf '\033[?25h\n' >&2
      return 1
    elif [ -z "$key" ]; then
      break
    fi
    # Move cursor up to redraw
    printf '\033[%dA\033[J' $((n + 4)) >&2
  done

  printf '\033[?25h' >&2
  UI_RESULT=""
  i=0
  while [ $i -lt $n ]; do
    if [ "${selected[$i]}" = 1 ]; then
      [ -n "$UI_RESULT" ] && UI_RESULT="$UI_RESULT,${items[$i]}" || UI_RESULT="${items[$i]}"
    fi
    i=$((i + 1))
  done
  return 0
}

# ui_choose <title> <item1> <item2> ...
# Sets $UI_CHOICE to 0-based index of chosen item (returns 1 on q/cancel).
ui_choose() {
  local title=$1; shift
  local opts=("$@")
  local n=${#opts[@]} cur=0 i key rest
  local C_CYAN=$'\033[36m' C_DIM=$'\033[90m' C_BOLD=$'\033[1m' C_RESET=$'\033[0m'

  printf '\033[?25l' >&2
  trap 'printf "\033[?25h" >&2' INT TERM

  while true; do
    printf '\n%s* %s%s\n' "$C_BOLD" "$title" "$C_RESET" >&2
    i=0
    while [ $i -lt $n ]; do
      if [ $i -eq $cur ]; then
        printf '│   %s>%s %s%d) %s%s\n' "$C_CYAN" "$C_RESET" "$C_BOLD" $((i + 1)) "${opts[$i]}" "$C_RESET" >&2
      else
        printf '│     %s%d) %s%s\n' "$C_DIM" $((i + 1)) "${opts[$i]}" "$C_RESET" >&2
      fi
      i=$((i + 1))
    done
    printf '  %s------------------------------------------------------------%s\n' "$C_DIM" "$C_RESET" >&2
    printf '  %s↑/↓ or 1-%d select · <enter> confirm · <q> quit%s\n' "$C_DIM" "$n" "$C_RESET" >&2

    IFS= read -rsn1 key < /dev/tty || { printf '\033[?25h' >&2; return 1; }
    if [ "$key" = $'\x1b' ]; then
      IFS= read -rsn2 rest < /dev/tty || true
      case "$rest" in
        "[A") cur=$(( (cur - 1 + n) % n )) ;;
        "[B") cur=$(( (cur + 1) % n )) ;;
      esac
    elif [ "$key" = "q" ] || [ "$key" = "Q" ]; then
      printf '\033[?25h\n' >&2
      return 1
    elif [ -z "$key" ]; then
      break
    elif [[ "$key" =~ ^[1-9]$ ]] && [ "$key" -le "$n" ]; then
      cur=$((key - 1))
      break
    fi
    printf '\033[%dA\033[J' $((n + 4)) >&2
  done

  printf '\033[?25h\n' >&2
  UI_CHOICE=$cur
  return 0
}
