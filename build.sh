#!/bin/sh
# Builds build/NotchProto.app with the Command Line Tools (no Xcode needed).
set -e
cd "$(dirname "$0")"
APP=build/NotchProto.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/Info.plist"
# Universal binary: one slice for Intel, one for Apple Silicon, joined with lipo.
SLICES=$(mktemp -d)
trap 'rm -rf "$SLICES"' EXIT
for ARCH in x86_64 arm64; do
  swiftc -O -target "$ARCH-apple-macos13.0" -o "$SLICES/$ARCH" Sources/*.swift
done
lipo -create "$SLICES/x86_64" "$SLICES/arm64" -output "$APP/Contents/MacOS/NotchProto"
# A fixed signing identity keeps the Accessibility permission across rebuilds.
IDENTITY="NotchProto Local Signing"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "Certificate '$IDENTITY' not found: ad-hoc signing, the permission will need to be granted again."
  codesign --force --sign - "$APP"
fi
echo "OK: $PWD/$APP"
