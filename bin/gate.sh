#!/usr/bin/env bash
# devguard gate: run a repo's .devguard/checks and guard commits and pushes with them.
#
#   gate.sh run [commit|push|all]   run checks for a stage (push and all include commit checks)
#   gate.sh install | uninstall     add or remove the pre-commit and pre-push hooks in this repo
#   gate.sh init                    write a commented .devguard/checks template and install hooks
#
# .devguard/checks has one check per line: "<stage> <name>: <command>", stage = commit | push.
# Commit checks run on every commit, so keep them fast; slow suites belong to push.
set -u

KIT_DIR=$(cd "$(dirname "$0")/.." && pwd -P)
CHECKS=.devguard/checks
MARK="# devguard-gate"

die() { echo "devguard gate: $*" >&2; exit 2; }

repo_top() { git rev-parse --show-toplevel 2>/dev/null || die "not inside a git repository"; }

# Prints "stage<TAB>name<TAB>command" per check; exits 2 naming the first malformed line.
parse_checks() {
  local n=0 line stage rest name cmd
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    case "$line" in "" | "#"*) continue ;; esac
    stage=${line%%[[:space:]]*}
    rest=$(printf '%s' "${line#"$stage"}" | sed 's/^[[:space:]]*//')
    case "$rest" in *:*) ;; *) die "$CHECKS line $n: expected '<stage> <name>: <command>'" ;; esac
    name=${rest%%:*}
    cmd=$(printf '%s' "${rest#*:}" | sed 's/^[[:space:]]*//')
    case "$stage" in commit | push) ;; *) die "$CHECKS line $n: stage must be 'commit' or 'push', got '$stage'" ;; esac
    printf '%s' "$name" | grep -Eq '^[A-Za-z0-9_-]+$' || die "$CHECKS line $n: name '$name' must be letters, digits, - or _"
    [ -n "$cmd" ] || die "$CHECKS line $n: empty command"
    printf '%s\t%s\t%s\n' "$stage" "$name" "$cmd"
  done < "$CHECKS"
}

cmd_run() {
  local want=${1:-all} parsed stage name cmd total=0 failed=""
  case "$want" in commit | push | all) ;; *) die "unknown stage '$want'" ;; esac
  cd "$(repo_top)" || exit 2
  [ -f "$CHECKS" ] || exit 0
  parsed=$(parse_checks) || exit 2
  if [ "$want" = commit ] && git diff --cached --name-only 2>/dev/null | grep -qx "$CHECKS"; then
    echo "devguard gate: this commit changes $CHECKS; review that no check was weakened or removed" >&2
  fi
  while IFS="$(printf '\t')" read -r stage name cmd; do
    [ -n "$name" ] || continue
    [ "$want" = commit ] && [ "$stage" != commit ] && continue
    total=$((total + 1))
    "$KIT_DIR/bin/verify.sh" "gate-$name" -- sh -c "$cmd" >&2 || failed="$failed $name"
  done <<EOF
$parsed
EOF
  if [ -z "$failed" ]; then
    echo "devguard gate: $total check(s) passed ($want)" >&2
    return 0
  fi
  for name in $failed; do echo "devguard gate: FAILED $name -> .verify/gate-$name.log" >&2; done
  echo "devguard gate: fix the failure and retry. Do not bypass with --no-verify." >&2
  return 1
}

hook_body() {
  cat <<EOF
#!/bin/sh
$MARK: runs .devguard/checks (remove with: devguard gate uninstall)
g='$KIT_DIR/bin/gate.sh'
if [ ! -x "\$g" ]; then
  echo "devguard gate: \$g not found; checks skipped. Reinstall with: devguard gate install" >&2
  exit 0
fi
exec "\$g" run $1
EOF
}

cmd_install() {
  local dir hook stage
  dir=$(cd "$(repo_top)" && git rev-parse --git-path hooks) || exit 2
  case "$dir" in /*) ;; *) dir="$(repo_top)/$dir" ;; esac
  mkdir -p "$dir"
  for stage in commit push; do
    hook="$dir/pre-$stage"
    if [ -e "$hook" ] && ! grep -qF "$MARK" "$hook"; then
      echo "devguard gate: $hook exists and is not ours; left untouched. Add this line to it: '$KIT_DIR/bin/gate.sh' run $stage"
      continue
    fi
    hook_body "$stage" > "$hook"
    chmod +x "$hook"
    echo "devguard gate: installed $hook"
  done
}

cmd_uninstall() {
  local dir hook
  dir=$(cd "$(repo_top)" && git rev-parse --git-path hooks) || exit 2
  case "$dir" in /*) ;; *) dir="$(repo_top)/$dir" ;; esac
  for hook in "$dir/pre-commit" "$dir/pre-push"; do
    [ -f "$hook" ] && grep -qF "$MARK" "$hook" && rm -f "$hook" && echo "devguard gate: removed $hook"
  done
  return 0
}

cmd_init() {
  cd "$(repo_top)" || exit 2
  if [ -e "$CHECKS" ]; then
    echo "devguard gate: $CHECKS already exists"
  else
    mkdir -p .devguard
    cat > "$CHECKS" <<'EOF'
# devguard gate: checks that must pass before a commit or a push.
# One per line: <stage> <name>: <command>
#   stage "commit" runs on every commit (keep it fast); "push" runs before push (slow suites).
# Agents: run `devguard check` before calling a task done, and never bypass with --no-verify.
#
# commit build: swift build
# push   test:  swift test
EOF
    echo "devguard gate: wrote $CHECKS (all lines commented; add your real commands)"
  fi
  cmd_install
}

case "${1:-}" in
  run) shift; cmd_run "$@" ;;
  install) cmd_install ;;
  uninstall) cmd_uninstall ;;
  init) cmd_init ;;
  *) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 64 ;;
esac
