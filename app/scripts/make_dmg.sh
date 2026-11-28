#!/bin/bash
# usage: make_dmg.sh <signed Stone.app> <out.dmg>
set -euo pipefail

APP="$1"
OUT="$2"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift "$HERE/dmg_background.swift" "$WORK/bg.png" 1
swift "$HERE/dmg_background.swift" "$WORK/bg@2x.png" 2
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$WORK/background.tiff" >/dev/null

mkdir "$WORK/src"
ditto "$APP" "$WORK/src/Stone.app"

rm -f "$OUT"
create-dmg \
  --volname "Stone" \
  --background "$WORK/background.tiff" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 112 \
  --text-size 13 \
  --icon "Stone.app" 160 190 \
  --hide-extension "Stone.app" \
  --app-drop-link 440 190 \
  --no-internet-enable \
  "$OUT" "$WORK/src"

