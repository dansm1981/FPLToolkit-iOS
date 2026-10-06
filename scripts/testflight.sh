#!/bin/zsh
# Archive FPLToolkit (Release) and upload it to TestFlight.
#
# Needs an App Store Connect API key, kept outside the repo (this repo is public):
#   ~/.appstoreconnect/fpltoolkit.env (chmod 600), setting
#     ASC_KEY_ID=...        the key's ID
#     ASC_ISSUER_ID=...     the Issuer ID shown above the keys list
#     ASC_KEY_PATH=...      the downloaded AuthKey_<id>.p8 (chmod 600)
# Steps for making the key: docs/mobile/testflight.md in the fpltoolkit-mobile workspace.
#
# The build number is the UTC time (yymmdd.HHMM), so every upload is higher than the last.
# Usage: scripts/testflight.sh
set -euo pipefail
cd "${0:A:h}/.."

source ~/.appstoreconnect/fpltoolkit.env
auth=(-allowProvisioningUpdates
      -authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

build=$(date -u +%y%m%d.%H%M)
out=~/Projects/claude-work/testflight/$build
mkdir -p "$out"
echo "Build $build → $out"

xcodebuild archive \
  -project FPLToolkit.xcodeproj -scheme FPLToolkit -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$out/FPLToolkit.xcarchive" \
  -derivedDataPath ~/Projects/claude-work/dd-release \
  CURRENT_PROJECT_VERSION="$build" \
  "${auth[@]}" > "$out/archive.log" 2>&1 \
  || { tail -40 "$out/archive.log"; exit 1; }
echo "Archived."

xcodebuild -exportArchive \
  -archivePath "$out/FPLToolkit.xcarchive" \
  -exportOptionsPlist Config/ExportOptions.plist \
  -exportPath "$out/export" \
  "${auth[@]}" > "$out/upload.log" 2>&1 \
  || { tail -40 "$out/upload.log"; exit 1; }
echo "Uploaded build $build. App Store Connect emails when it has processed (usually 5–15 minutes)."
