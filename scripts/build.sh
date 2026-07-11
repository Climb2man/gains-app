#!/usr/bin/env bash
# The Swift verify gate (autonomous, no human): regenerate the project from project.yml, build for
# the booted simulator, install, launch, and screenshot to /tmp/gains_swift.png. Run after changes.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate >/dev/null
# NO CODE_SIGNING_ALLOWED=NO here: it would override project.yml's AD-HOC signing and produce an
# UNSIGNED app whose keychain-access-groups entitlement doesn't exist, every SecItem* call then
# fails with -34018, silently breaking the encrypted store's master key, the AI key save, and the
# Whoop session. Ad-hoc ("-") signs on the simulator with no Apple account, keeping the loop autonomous.
xcodebuild -project Gains.xcodeproj -scheme Gains \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .build -quiet build

APP="$(find .build/Build/Products -maxdepth 3 -name 'Gains.app' | head -1)"
[ -n "$APP" ] || { echo "BUILD FAILED: no Gains.app produced"; exit 1; }

BUNDLE="$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")"
xcrun simctl install booted "$APP"
# `-sampleData YES`: the screenshot loop wants the POPULATED demo container (full tabs without a
# live Whoop link). A plain launch, e.g. tapping the icon, uses the REAL container, like the phone.
xcrun simctl launch booted "$BUNDLE" -sampleData YES >/dev/null
sleep 4 # cold first-render can take >2s after a fresh install; a too-early shot reads as a blank app
xcrun simctl io booted screenshot /tmp/gains_swift.png >/dev/null 2>&1 || true
echo "OK build+launch: $APP"
