#!/bin/bash
set -euo pipefail

# Only increment on Archive builds
if [ "${ACTION:-}" != "install" ]; then
    exit 0
fi

PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST")
NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD_NUMBER" "$PLIST"

# Also update the project file so it persists
cd "${SRCROOT}"
agvtool new-version -all "$NEW_BUILD_NUMBER" > /dev/null 2>&1 || true

echo "Build number incremented: $BUILD_NUMBER → $NEW_BUILD_NUMBER"
