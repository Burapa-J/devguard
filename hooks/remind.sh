#!/usr/bin/env bash
# Printed into the agent's context on session start after a compaction (Claude Code SessionStart hook,
# matcher "compact"). Keep it short: it is paid for in tokens every time it fires.
cat <<'EOF'
[agent-kit] Context was compacted. Re-load the `verified-dev` skill before continuing any code task.
Resume from the task list. Every "done" still needs evidence (agent-verify log + exit code).
EOF
