#!/bin/sh
# Builds build/NotchProto.app with the Command Line Tools (no Xcode needed).
set -e
cd "$(dirname "$0")"
APP=build/NotchProto.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -target x86_64-apple-macos13.0 -o "$APP/Contents/MacOS/NotchProto" Sources/*.swift
# A fixed signing identity keeps the Accessibility permission across rebuilds.
IDENTITY="NotchProto Local Signing"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "Certificate '$IDENTITY' not found: ad-hoc signing, the permission will need to be granted again."
  codesign --force --sign - "$APP"
fi
echo "OK: $PWD/$APP"
