#!/usr/bin/env bash
# One-command setup on a new machine:
#
#   gh api -H 'Accept: application/vnd.github.raw' repos/Burapa-J/A69-012-agent-kit/contents/bootstrap.sh | bash
#
# Pass install options after "bash -s --", e.g. ... | bash -s -- --with=codegraph,projectmem,rtk,context-mode
# Installs missing prerequisites with Homebrew (macOS), clones the kit, and runs install.sh.
set -eu

# Wrapped in a function so the whole script is read before anything runs (safe with "| bash").
main() {

  REPO="Burapa-J/A69-012-agent-kit"
  DEST=${AGENT_KIT_DIR:-}

  say() { printf '==> %s\n' "$*"; }
  die() { printf 'error: %s\n' "$*" >&2; exit 1; }

  # Reuse an existing clone if devguard is already installed.
  if [ -z "$DEST" ] && [ -L "$HOME/.local/bin/devguard" ]; then
    DEST=$(cd "$(dirname "$(readlink "$HOME/.local/bin/devguard")")/.." && pwd -P)
  elif [ -z "$DEST" ] && [ -L "$HOME/.local/bin/agent-kit" ]; then
    DEST=$(cd "$(dirname "$(readlink "$HOME/.local/bin/agent-kit")")/.." && pwd -P)
  fi
  DEST=${DEST:-$HOME/.local/share/agent-kit/src}

  missing=""
  command -v git >/dev/null 2>&1 || missing="$missing git"
  command -v jq >/dev/null 2>&1 || missing="$missing jq"
  command -v python3 >/dev/null 2>&1 || missing="$missing python3"
  command -v npm >/dev/null 2>&1 || missing="$missing node"
  command -v xcbeautify >/dev/null 2>&1 || missing="$missing xcbeautify"
  command -v ast-grep >/dev/null 2>&1 || missing="$missing ast-grep"
  if [ -n "$missing" ]; then
    if command -v brew >/dev/null 2>&1; then
      say "Installing with Homebrew:$missing"
      # shellcheck disable=SC2046  # one argument per tool is intended
      brew install $(printf '%s' "$missing" | sed 's/python3/python/') < /dev/null
    else
      die "missing:$missing. Install Homebrew (https://brew.sh) or these tools, then run again."
    fi
  fi

  if [ -d "$DEST/.git" ]; then
    say "Updating $DEST"
    git -C "$DEST" pull --ff-only < /dev/null
  else
    say "Cloning $REPO to $DEST"
    mkdir -p "$(dirname "$DEST")"
    if command -v gh >/dev/null 2>&1; then
      gh repo clone "$REPO" "$DEST" < /dev/null
    else
      git clone "https://github.com/$REPO.git" "$DEST" < /dev/null
    fi
  fi

  say "Installing (quit Claude Code, VS Code and Antigravity first for a clean config write)"
  "$DEST/install.sh" "$@" < /dev/null

  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *)
      rc="${ZDOTDIR:-$HOME}/.zshrc"
      if ! grep -qs 'HOME/.local/bin' "$rc"; then
        # shellcheck disable=SC2016  # written literally into .zshrc
        printf '\n%s\n' 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
        say "Added ~/.local/bin to PATH in $rc"
      fi
      ;;
  esac

  say "Done. Open a new terminal, restart your agents, then run: devguard status"
}

main "$@"
