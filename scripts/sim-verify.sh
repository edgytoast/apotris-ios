#!/usr/bin/env bash
# The verification drill (charter rules 6+7): build both app targets, run the
# unit + UI test suites on the project's own simulators, and capture content
# screenshots into docs/screenshots/. Loud failures throughout.
set -euo pipefail
cd "$(dirname "$0")/.."

# Device UDIDs: pass them in (your lane's devices; NEVER create simulators --
# see ~/dev/CLAUDE.md), e.g.
#   IOS_UDID=<iPhone 17 Pro Max udid> VISION_UDID=<Apple Vision Pro udid> \
#     scripts/sim-verify.sh
# or as two positional args. Falls back to docs/sim.md (gitignored, local).
IOS_UDID="${1:-${IOS_UDID:-}}"
VISION_UDID="${2:-${VISION_UDID:-}}"
if [ -z "$IOS_UDID" ] && [ -f docs/sim.md ]; then
  IOS_UDID=$(grep 'apotris-ios-dev' docs/sim.md | grep -oE '[A-F0-9-]{36}' || true)
fi
if [ -z "$VISION_UDID" ] && [ -f docs/sim.md ]; then
  VISION_UDID=$(grep 'apotris-vision-dev' docs/sim.md | grep -oE '[A-F0-9-]{36}' || true)
fi
[ -n "$IOS_UDID" ] && [ -n "$VISION_UDID" ] || {
  echo "error: need IOS_UDID and VISION_UDID (env or args); see xcrun simctl list devices available" >&2
  exit 1
}
# Shut down what we booted, even on failure (program rule: never leave a
# simulator running).
trap 'xcrun simctl shutdown "$IOS_UDID" 2>/dev/null || true; xcrun simctl shutdown "$VISION_UDID" 2>/dev/null || true' EXIT
SHOTS=docs/screenshots

scripts/build-ios-core.sh ios-sim
scripts/build-ios-core.sh xros-sim

cd app
xcodegen generate

echo "=== unit + UI tests (iPhone sim) ==="
xcrun simctl boot "$IOS_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$IOS_UDID" -b
xcodebuild -project Apotris.xcodeproj -scheme Apotris \
  -destination "id=$IOS_UDID" -quiet test

echo "=== visionOS build + boot smoke ==="
xcodebuild -project Apotris.xcodeproj -scheme ApotrisVision \
  -destination "id=$VISION_UDID" -quiet build
VAPP=$(xcodebuild -project Apotris.xcodeproj -scheme ApotrisVision \
  -destination "id=$VISION_UDID" -showBuildSettings build 2>/dev/null |
  grep -m1 "TARGET_BUILD_DIR" | sed 's/.*= //')/ApotrisVision.app
xcrun simctl boot "$VISION_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$VISION_UDID" -b
xcrun simctl install "$VISION_UDID" "$VAPP"
xcrun simctl launch "$VISION_UDID" dev.austinbuilds.ApotrisVision
sleep 8
xcrun simctl io "$VISION_UDID" screenshot "../$SHOTS/vision-sim-boot.png"

echo "=== iPhone content screenshot ==="
APP=$(xcodebuild -project Apotris.xcodeproj -scheme Apotris \
  -destination "id=$IOS_UDID" -showBuildSettings build 2>/dev/null |
  grep -m1 "TARGET_BUILD_DIR" | sed 's/.*= //')/Apotris.app
xcrun simctl install "$IOS_UDID" "$APP"
xcrun simctl terminate "$IOS_UDID" dev.austinbuilds.Apotris 2>/dev/null || true
xcrun simctl launch "$IOS_UDID" dev.austinbuilds.Apotris
sleep 8
xcrun simctl io "$IOS_UDID" screenshot "../$SHOTS/ios-sim-current.png"

echo "sim-verify OK — screenshots in $SHOTS/"
