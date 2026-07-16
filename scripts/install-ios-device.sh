#!/bin/sh

set -eu

if [ "$#" -gt 0 ] && [ "$1" = "--" ]; then
  shift
fi

if [ "$#" -ne 2 ]; then
  echo "Usage: pnpm ios:device-install -- DEVICE_ID DEVELOPMENT_TEAM_ID" >&2
  exit 64
fi

device_id="$1"
development_team_id="$2"
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(dirname "$script_directory")
developer_directory="/Applications/Xcode-beta.app/Contents/Developer"
derived_data_path="$repository_root/DerivedData/device"
app_path="$derived_data_path/Build/Products/Debug-iphoneos/VoxaCue.app"

cd "$repository_root"
pnpm ios:generate

DEVELOPER_DIR="$developer_directory" xcodebuild \
  -project ios/VoxaCue.xcodeproj \
  -scheme VoxaCue \
  -configuration Debug \
  -destination "id=$device_id" \
  -derivedDataPath "$derived_data_path" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$development_team_id" \
  build

DEVELOPER_DIR="$developer_directory" xcrun devicectl device install app \
  --device "$device_id" \
  "$app_path"

DEVELOPER_DIR="$developer_directory" xcrun devicectl device process launch \
  --device "$device_id" \
  com.amaarmc.voxacue
