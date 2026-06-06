#!/usr/bin/env bash
# Driver for soundforge-clearwave DSP test suite.
# Usage:
#   bash smoke.sh            → run all 23 DSP unit tests
#   bash smoke.sh --filter rms  → run tests matching pattern
#   bash smoke.sh --check    → run tests + report deprecation warnings
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TESTS_DIR="$ROOT/tests"

FILTER=""
WARN_MODE=""

for arg in "$@"; do
  case "$arg" in
    --filter) shift; FILTER="${1:-}" ;;
    --filter=*) FILTER="${arg#--filter=}" ;;
    --check) WARN_MODE="--warning-mode all" ;;
  esac
done

cd "$TESTS_DIR"

if [ -n "$FILTER" ]; then
  gradle test --no-daemon --tests "*${FILTER}*" $WARN_MODE
else
  gradle test --no-daemon $WARN_MODE
fi
