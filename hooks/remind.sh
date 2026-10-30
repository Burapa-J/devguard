#!/usr/bin/env bash
# Printed into the agent's context on session start after a compaction (Claude Code SessionStart hook,
# matcher "compact"). Keep it short: it is paid for in tokens every time it fires.
cat <<'EOF'
[devguard] Context was compacted. Re-load the `verified-dev` skill before continuing any code task.
Resume from the task list. Every "done" needs a one-line verification receipt (command, exit code, verdict, and .verify/<name>.log); paste raw logs only on failure.
EOF
