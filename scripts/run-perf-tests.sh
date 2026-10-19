#!/bin/zsh
# Runs the performance tests against a Release build.
# Usage: scripts/run-perf-tests.sh [simulator name]
# Env: ONLY=NightPdfUITests/PerformanceTests/<test> runs one test.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG=Release ONLY="${ONLY:-NightPdfUITests/PerformanceTests}" exec scripts/run-ui-tests.sh "$@"
