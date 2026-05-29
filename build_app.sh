#!/usr/bin/env bash
set -euo pipefail

APP_NAME="牛马补水站"
BUNDLE_DIR=".build/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
SDK_PATH="${SDK_PATH:-/Library/Developer/CommandLineTools/SDKs/MacOSX14.5.sdk}"

mkdir -p ".build/release"

clang \
  -fobjc-arc \
  -isysroot "${SDK_PATH}" \
  -target arm64-apple-macosx13.0 \
  -framework AppKit \
  -framework QuartzCore \
  "Sources/WaterReminder/main.m" \
  -o ".build/release/WaterReminder"

rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp ".build/release/WaterReminder" "${MACOS_DIR}/WaterReminder"
cp "Info.plist" "${CONTENTS_DIR}/Info.plist"
cp "Assets/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
cp "Assets/AppIcon.png" "${RESOURCES_DIR}/AppIcon.png"
cp "Assets/CupGlass.png" "${RESOURCES_DIR}/CupGlass.png"
cp "Assets/OnboardingCoach.png" "${RESOURCES_DIR}/OnboardingCoach.png"

chmod +x "${MACOS_DIR}/WaterReminder"
codesign --force --deep --sign - "${BUNDLE_DIR}" >/dev/null

echo "Built ${BUNDLE_DIR}"
echo "Run with: open '${BUNDLE_DIR}'"
