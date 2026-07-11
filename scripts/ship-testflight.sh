#!/usr/bin/env bash
# ship-testflight.sh, bump the build number, archive, export, and upload a new Gains build to TestFlight.
#
# SIGNING: archive + export use your Xcode-account SESSION (be signed into Xcode → Settings → Accounts),
# because the App Store Connect API key's command-line provisioning auth fails even though the same key
# uploads fine. The UPLOAD uses the API key from the gitignored repo-root .env (ASC_KEY_ID / ASC_ISSUER_ID;
# the .p8 lives at ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8). See docs/testflight-checklist.md.
#
# The same .env carries DEVELOPMENT_TEAM. It is NOT committed (public repo, the team ID ties it to a
# personal Apple account), so this script is what injects it: exported for XcodeGen to substitute into
# project.yml, and rendered into ExportOptions.plist from ExportOptions.plist.template. Copy .env.example.
#
# Prereqs (one-time, already done for the first ship): bundle ID com.nxw.gains registered, a device
# registered to the team, the App Store Connect app record created, .env populated.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
IOS="$(cd "$HERE/.." && pwd)"

[ -f "$IOS/.env" ] || { echo "✗ missing $IOS/.env (copy .env.example, needs DEVELOPMENT_TEAM, ASC_KEY_ID, ASC_ISSUER_ID)"; exit 1; }
set -a; source "$IOS/.env"; set +a
: "${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM in .env}"
: "${ASC_KEY_ID:?set ASC_KEY_ID in .env}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID in .env}"

cd "$IOS"

# Bump the build number, App Store Connect rejects a reused CFBundleVersion. The base
# CURRENT_PROJECT_VERSION flows to both targets via $(CURRENT_PROJECT_VERSION).
CUR="$(awk -F'"' '/^[[:space:]]*CURRENT_PROJECT_VERSION:/{print $2; exit}' project.yml)"
NEXT="$((CUR + 1))"
sed -i '' "s/CURRENT_PROJECT_VERSION: \"$CUR\"/CURRENT_PROJECT_VERSION: \"$NEXT\"/" project.yml
echo "==> build number $CUR -> $NEXT"

# `set -a` above already exported DEVELOPMENT_TEAM, XcodeGen expands the "${DEVELOPMENT_TEAM}" in
# project.yml from the environment. Unset it would silently generate an empty team and fail signing
# later with an opaque error, hence the hard `:?` check above.
echo "==> xcodegen generate"
xcodegen generate >/dev/null

# Render the gitignored export config from the committed template (team ID stays out of git).
echo "==> render ExportOptions.plist (team $DEVELOPMENT_TEAM)"
sed "s/__TEAM_ID__/$DEVELOPMENT_TEAM/" "$IOS/ExportOptions.plist.template" > "$IOS/ExportOptions.plist"

echo "==> archive (Release, device; Xcode-session signing)"
rm -rf /tmp/Gains.xcarchive
xcodebuild archive -project Gains.xcodeproj -scheme Gains \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath /tmp/Gains.xcarchive -allowProvisioningUpdates >/tmp/gains-archive.log 2>&1 \
  || { echo "✗ archive failed:"; tail -15 /tmp/gains-archive.log; exit 1; }

echo "==> export App Store .ipa"
rm -rf /tmp/GainsExport
xcodebuild -exportArchive -archivePath /tmp/Gains.xcarchive -exportPath /tmp/GainsExport \
  -exportOptionsPlist "$IOS/ExportOptions.plist" -allowProvisioningUpdates >/tmp/gains-export.log 2>&1 \
  || { echo "✗ export failed:"; tail -15 /tmp/gains-export.log; exit 1; }

echo "==> upload to TestFlight"
xcrun altool --upload-app -f /tmp/GainsExport/Gains.ipa -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo "==> done. Commit the bumped project.yml, then watch App Store Connect -> Gains IOS -> TestFlight."
