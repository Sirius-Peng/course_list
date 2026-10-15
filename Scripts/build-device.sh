#!/bin/bash
# Build the complete companion bundle, with literal App Group provisioning IDs.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${COURSELIST_TEAM:?Set DEVELOPMENT_TEAM}"
: "${COURSELIST_APP_GROUP:?Set a registered App Group}"
: "${IPHONE_DEVICE_UDID:?Set the connected iPhone UDID}"
mkdir -p .implementation/logs
COURSELIST_PROJECT_NAME=CourseListDevice COURSELIST_INCLUDE_WATCH=1 python3 Scripts/generate-iphone-project.py
SDK="$(basename "$(xcrun --sdk iphoneos --show-sdk-path)" .sdk | tr '[:upper:]' '[:lower:]')"
if [[ -n "${IOS_RUNTIME_BUILD:-}" ]]; then
    RESTORE="$(xcrun simctl runtime match list -j | python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]].get("userOverriddenBuild", "--default"))' "$SDK")"
    trap 'xcrun simctl runtime match set "$SDK" "$RESTORE"' EXIT
    xcrun simctl runtime match set "$SDK" "$IOS_RUNTIME_BUILD"
fi
if [[ -n "${WATCH_DEVICE_UDID:-}" ]]; then
    xcodebuild -project CourseListDevice.xcodeproj -scheme CourseListWatchApp \
        -destination "platform=watchOS,id=$WATCH_DEVICE_UDID" -configuration Debug -derivedDataPath .build-device \
        -allowProvisioningUpdates -allowProvisioningDeviceRegistration build > .implementation/logs/watch-device-build.log 2>&1
fi
xcodebuild -project CourseListDevice.xcodeproj -scheme CourseListApp \
    -destination "platform=iOS,id=$IPHONE_DEVICE_UDID" -configuration Debug -derivedDataPath .build-device \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration build > .implementation/logs/full-device-build.log 2>&1
ARGS=(.build-device/Build/Products/Debug-iphoneos/CourseListApp.app --group "$COURSELIST_APP_GROUP" --iphone-udid "$IPHONE_DEVICE_UDID")
[[ -z "${WATCH_DEVICE_UDID:-}" ]] || ARGS+=(--watch-udid "$WATCH_DEVICE_UDID")
python3 Scripts/verify-bundle.py "${ARGS[@]}"
echo 'DEVICE_BUILD: iPhone + Watch + both widgets built and signed'
