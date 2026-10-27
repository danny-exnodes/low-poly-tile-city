#!/usr/bin/env bash
# Build the web app with the QA debug hook and serve it in the background.
# Usage: serve.sh [port] [extra flutter build args...]
# Never stop servers with `pkill -f` (it matches and kills the calling shell);
# use `fuser -k <port>/tcp` instead.
set -euo pipefail
PORT="${1:-8082}"; shift || true
cd "$(git rev-parse --show-toplevel)"
OUT="build/web_qa_$PORT"
flutter build web --release --dart-define=DEBUG_HOOK=true -o "$OUT" "$@" >/dev/null 2>&1
fuser -k "$PORT/tcp" >/dev/null 2>&1 || true
(cd "$OUT" && nohup python3 -m http.server "$PORT" >/dev/null 2>&1 &)
sleep 1
echo "serving $OUT on http://localhost:$PORT/"
