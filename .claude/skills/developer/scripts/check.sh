#!/usr/bin/env bash
# The pre-push gate: analyze, test (includes the benchmark), build.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
flutter analyze
flutter test
flutter build web --release >/dev/null
echo "check: OK"
