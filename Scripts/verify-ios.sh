#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .implementation/logs
python3 Scripts/generate-iphone-project.py > .implementation/logs/iphone-generation.log
# Optional SDK/runtime mismatch workaround. The prior matching state is restored on exit.
SDK="$(basename "$(xcrun --sdk iphoneos --show-sdk-path)" .sdk | tr '[:upper:]' '[:lower:]')"
RESTORE=""
if [[ -n "${IOS_RUNTIME_BUILD:-}" ]]; then
    RESTORE="$(xcrun simctl runtime match list -j | python3 -c 'import json,sys; v=json.load(sys.stdin)[sys.argv[1]]; print(v.get("userOverriddenBuild", "--default"))' "$SDK")"
    trap 'xcrun simctl runtime match set "$SDK" "$RESTORE"' EXIT
    xcrun simctl runtime match set "$SDK" "$IOS_RUNTIME_BUILD"
fi
DEVICE="${IOS_SIMULATOR_ID:-$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); xs=[v for k,vs in d["devices"].items() if "iOS-26" in k for v in vs if v["name"].startswith("iPhone")]; assert xs,"No iOS 26 simulator installed"; print(next((v for v in xs if v["state"]=="Booted"),xs[0])["udid"])')}"
ACTION="${1:-build}"
[[ "$ACTION" == build || "$ACTION" == test ]]
xcodebuild -project CourseListiPhoneOnly.xcodeproj -scheme CourseListApp \
    -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath .build-xcode \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- "$ACTION" > ".implementation/logs/ios-$ACTION.log" 2>&1
if [[ "$ACTION" == test ]]; then
    grep 'Executed 8 tests, with 0 failures' .implementation/logs/ios-test.log >/dev/null
    echo 'IOS_UI: 8 tests passed; 0 failures'
else
    grep '\*\* BUILD SUCCEEDED \*\*' .implementation/logs/ios-build.log >/dev/null
    echo 'IOS_BUILD: App and Widget extension built successfully'
fi
