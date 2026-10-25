#!/bin/bash
# Builds ClaudeUsageBar.app (ad-hoc signed) and a distributable zip.
set -euo pipefail
cd "$(dirname "$0")"

APP="ClaudeUsageBar.app"
rm -rf "$APP" ClaudeUsageBar.zip
mkdir -p "$APP/Contents/MacOS"

# Universal binary (Apple Silicon + Intel), macOS 13+
swiftc -O -target arm64-apple-macos13.0 main.swift -o .arm64.bin
swiftc -O -target x86_64-apple-macos13.0 main.swift -o .x86_64.bin
lipo -create .arm64.bin .x86_64.bin -output "$APP/Contents/MacOS/ClaudeUsageBar"
rm -f .arm64.bin .x86_64.bin
cp Info.plist "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"
ditto -c -k --keepParent "$APP" ClaudeUsageBar.zip
echo "Built $APP and ClaudeUsageBar.zip"
