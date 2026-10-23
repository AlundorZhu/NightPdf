#!/bin/zsh
# Builds NightPdf, seeds the test PDFs into the simulator, and runs the UI tests.
# Usage: scripts/run-ui-tests.sh [simulator name] [screenshot dir]
# Env: ONLY=<test identifier> runs just that test; CONFIG=Release builds Release.
# The performance tests are skipped unless ONLY selects them (see run-perf-tests.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${1:-iPhone 17 Pro}"
SHOTS="${2:-}"
CONFIG="${CONFIG:-Debug}"
DERIVED="build/DerivedData"
UDID=$(xcrun simctl list devices available | grep -F "$DEVICE (" | tail -1 | grep -oE '[0-9A-F-]{36}')

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

[[ -f TestAssets/large.pdf ]] || swift TestAssets/tools/make-large-pdf.swift

xcodebuild -project NightPdf.xcodeproj -scheme NightPdf -testPlan AllTests -configuration "$CONFIG" -destination "id=$UDID" \
    -derivedDataPath "$DERIVED" build-for-testing -quiet
xcrun simctl install "$UDID" "$DERIVED/Build/Products/$CONFIG-iphonesimulator/NightPdf.app"
DOCS="$(xcrun simctl get_app_container "$UDID" com.alundor.NightPdf data)/Documents"
mkdir -p "$DOCS"
cp TestAssets/sample.pdf "$DOCS/Sample Paper.pdf"
cp TestAssets/edge-cases.pdf "$DOCS/Edge Cases.pdf"
cp TestAssets/large.pdf "$DOCS/Large.pdf"

[[ -n "$SHOTS" ]] && mkdir -p "$SHOTS" && export TEST_RUNNER_NIGHTPDF_SCREENSHOTS="$(cd "$SHOTS" && pwd)"
if [[ -n "${ONLY:-}" ]]; then SELECT=(-only-testing:"$ONLY"); else SELECT=(-skip-testing:NightPdfUITests/PerformanceTests); fi
xcodebuild -project NightPdf.xcodeproj -scheme NightPdf -testPlan AllTests -configuration "$CONFIG" -destination "id=$UDID" \
    -derivedDataPath "$DERIVED" test-without-building "${SELECT[@]}"
