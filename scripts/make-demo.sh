#!/bin/sh
# Regenerates assets/demo.gif. Optional argument: a folder for a few still frames.
set -e
cd "$(dirname "$0")/.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
swiftc -O -parse-as-library -o "$WORK/make-demo" scripts/make-demo.swift \
  Sources/IslandView.swift Sources/GlassContainer.swift Sources/NowPlaying.swift Sources/SourceApp.swift
"$WORK/make-demo" assets/demo.gif "$@"
