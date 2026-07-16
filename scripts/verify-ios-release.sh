#!/bin/sh
set -eu

export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
derived_data_path=/tmp/voxa-cue-release-derived-data

pnpm ios:generate
xcodebuild \
  -project ios/VoxaCue.xcodeproj \
  -scheme VoxaCue \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$derived_data_path" \
  CODE_SIGNING_ALLOWED=NO \
  build

info_plist="$derived_data_path/Build/Products/Release-iphoneos/VoxaCue.app/Info.plist"
configured_url=$(/usr/libexec/PlistBuddy -c 'Print :VoxaAPIBaseURL' "$info_plist")
configured_token=$(/usr/libexec/PlistBuddy -c 'Print :VoxaDemoAPIToken' "$info_plist")

test "$configured_url" = "https://example.invalid"
test -z "$configured_token"
plutil -lint ios/VoxaCue/Resources/PrivacyInfo.xcprivacy
