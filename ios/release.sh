#!/bin/zsh
# Build Study Stash for iPhone and iPad and send it to App Store Connect (TestFlight first, then the App Store).
#   ios/release.sh            archive, then upload
#   ios/release.sh --local    archive and export an .ipa into ios/build/export, without uploading
# Needs: Xcode signed in to the Apple ID on team 6K4VZU48G9 (Xcode → Settings → Accounts), and the app made once in
# App Store Connect (see RELEASE.md). Bump MARKETING_VERSION / CURRENT_PROJECT_VERSION in project.yml for each upload.
set -euo pipefail
cd "$(dirname "$0")"
command -v xcodegen >/dev/null || { echo "brew install xcodegen" >&2; exit 1; }
xcodegen generate
archive=build/StudyStash.xcarchive
rm -rf "$archive" build/export
xcodebuild -project StudyStash.xcodeproj -scheme StudyStash -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$archive" -allowProvisioningUpdates archive
method=app-store-connect
destination=upload
[[ "${1:-}" == "--local" ]] && destination=export
cat > build/export.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>$method</string>
  <key>destination</key><string>$destination</string>
  <key>teamID</key><string>6K4VZU48G9</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><true/>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist build/export.plist -exportPath build/export -allowProvisioningUpdates
echo "Done: $([[ $destination == upload ]] && echo 'uploaded; it shows in TestFlight in App Store Connect in 5–15 minutes' || echo build/export)"
