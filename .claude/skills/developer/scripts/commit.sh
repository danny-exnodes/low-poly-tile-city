#!/usr/bin/env bash
# Commit staged changes with the attribution trailer.
# Usage: commit.sh "type: subject" ["body line" ...]
# Trailers: use exactly the lines the current session asks for, via
#   CLAUDE_COAUTHOR="Claude <noreply@anthropic.com>"   (default)
#   CLAUDE_SESSION_URL="https://claude.ai/code/session_..."   (optional)
set -euo pipefail
[ $# -ge 1 ] || { echo "usage: commit.sh \"type: subject\" [body...]" >&2; exit 1; }
subject="$1"; shift
msg="$subject"
if [ $# -gt 0 ]; then
  msg+=$'\n'
  for line in "$@"; do msg+=$'\n'"$line"; done
fi
msg+=$'\n\nCo-Authored-By: '"${CLAUDE_COAUTHOR:-Claude <noreply@anthropic.com>}"
if [ -n "${CLAUDE_SESSION_URL:-}" ]; then msg+=$'\n'"Claude-Session: $CLAUDE_SESSION_URL"; fi
git commit -m "$msg"
