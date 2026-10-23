#!/bin/zsh
# Captures the App Store screenshots into AppStore/screenshots/<device>/.
# Usage: scripts/take-screenshots.sh [simulator name ...]
# Defaults to the two sizes App Store Connect requires: 6.9" iPhone and 13" iPad.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICES=("$@")
(( ${#DEVICES} )) || DEVICES=("iPhone 17 Pro Max" "iPad Pro 13-inch (M5)")
DERIVED="build/DerivedData"

[[ -f AppStore/showcase.pdf ]] || (cd AppStore && pdflatex -interaction=batchmode showcase.tex && pdflatex -interaction=batchmode showcase.tex)

xcodebuild -project NightPdf.xcodeproj -scheme NightPdf -testPlan AllTests -configuration Debug \
    -destination "generic/platform=iOS Simulator" -derivedDataPath "$DERIVED" build-for-testing -quiet

for DEVICE in "${DEVICES[@]}"; do
    UDID=$(xcrun simctl list devices available | grep -F "$DEVICE (" | tail -1 | grep -oE '[0-9A-F-]{36}')
    xcrun simctl boot "$UDID" 2>/dev/null || true
    xcrun simctl bootstatus "$UDID" -b >/dev/null
    xcrun simctl ui "$UDID" appearance dark
    xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiBars 3 \
        --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

    xcrun simctl install "$UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/NightPdf.app"
    DOCS="$(xcrun simctl get_app_container "$UDID" com.alundor.NightPdf data)/Documents"
    mkdir -p "$DOCS"
    cp AppStore/showcase.pdf "$DOCS/How Owls See in the Dark.pdf"

    SHOTS="AppStore/screenshots/$DEVICE"
    rm -rf "$SHOTS" && mkdir -p "$SHOTS"
    TEST_RUNNER_NIGHTPDF_APPSTORE=1 TEST_RUNNER_NIGHTPDF_SCREENSHOTS="$(cd "$SHOTS" && pwd)" \
        xcodebuild -project NightPdf.xcodeproj -scheme NightPdf -testPlan AllTests -configuration Debug \
        -destination "id=$UDID" -derivedDataPath "$DERIVED" test-without-building \
        -only-testing:NightPdfUITests/AppStoreScreenshots -quiet
    xcrun simctl status_bar "$UDID" clear
done
