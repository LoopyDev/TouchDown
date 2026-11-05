#!/bin/zsh
# Builds TouchDown (Release), installs it to /Applications and launches it.
#
# By default the app is signed ad-hoc, which macOS treats as a brand-new app on every
# rebuild, so Accessibility has to be granted again each time. Set SIGN_IDENTITY to a code
# signing certificate in your keychain to keep permissions across rebuilds, e.g.
#
#   SIGN_IDENTITY="Apple Development" scripts/install-local.sh
#
# (`security find-identity -v -p codesigning` lists the ones you have.)

set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
identity="${SIGN_IDENTITY:--}"
app="build/dd/Build/Products/Release/TouchDown.app"

log=build/install-local.log
mkdir -p build
if ! xcodebuild -project "Touch Up.xcodeproj" -scheme "Touch Up" -configuration Release \
        -derivedDataPath build/dd build > "$log" 2>&1; then
    grep -E "error:" "$log" || tail -20 "$log"
    echo "Build failed, nothing installed. Full log: $log" >&2
    exit 1
fi

# Re-sign rather than asking Xcode to sign: Xcode wants a team and provisioning set up in the
# project for a real certificate, but codesign just needs the identity. Inside-out, keeping
# the entitlements Xcode generated.
if [[ "$identity" != "-" ]]; then
    codesign --force --sign "$identity" "$app/Contents/Frameworks/TouchUpCore.framework"
    codesign --force --sign "$identity" --preserve-metadata=entitlements,flags "$app"
fi

codesign --verify --deep --strict "$app"

osascript -e 'tell application id "io.github.loopydev.TouchDown" to quit' 2>/dev/null || true
sleep 1
rm -rf /Applications/TouchDown.app
ditto "$app" /Applications/TouchDown.app
open /Applications/TouchDown.app

echo "Installed /Applications/TouchDown.app ($(codesign -dvv /Applications/TouchDown.app 2>&1 | grep -m1 '^Authority=' || echo 'ad-hoc'))"
