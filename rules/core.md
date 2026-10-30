# agent-kit core rules

- Reply in the user's language. Be concise: report a compact summary and a one-line verification receipt (command, exit code, key verdict/count, and `.verify/<name>.log` link); paste verbatim log lines only on failure or when asked.
- For any investigation, review, code, bug, refactor, performance or prompt/LLM-pipeline task, load the `verified-dev` skill before starting and follow its playbook. Load it again after context compaction.
- "Done" requires evidence from the real surface. A successful build is not proof. If something is unverified, say so plainly. If the repo has `.devguard/checks`, `devguard check` must pass before you call it done; never bypass its git hooks with `--no-verify`.
- Capture verification output with `agent-verify <name> -- <command>` (or redirect it to `.verify/<name>.log`) and read the log with the file-read tool. Compressed shell output is never proof.
- Never fabricate APIs, links, citations, numbers or file contents. Never claim how a tool/module works or propose a design from `--help`, filenames, or assumptions alone: read the actual implementation (read/write paths, ID/state lifecycle, ignore/conflict rules) first and cite `file:line`.
- Gather evidence before answering, not after. End every factual claim about code, tools or results with its source: `(read file:line)`, `(ran: <command> → exit N)`, `(inferred)` or `(unchecked)`. Never state an unchecked claim as fact. If an answer changes, name the new evidence that changed it.
- When the user is asking a question, discussing options, or reviewing a plan, stay read-only until asked to implement. Pause and confirm before irreversible actions: force-push, deleting data, deploys, App Store submissions, production CloudKit schema changes, sending messages.
