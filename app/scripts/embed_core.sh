#!/bin/zsh
set -euo pipefail

src="${STONE_CORE_OUT}/${STONE_CORE_FRAMEWORK}.framework"
dst="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"

if [[ ! -d "$src" ]]; then
  echo "error: ${src} not found; build StoneCore first" >&2
  exit 1
fi

mkdir -p "$dst"
rsync -a --delete "$src" "$dst/"

# Component builds: helpers find their dylibs relative to the app's parent
# directory, as Chromium.app does inside the out directory.
for lib in "${STONE_CORE_OUT}"/*.dylib(N); do
  ln -sfn "$lib" "${TARGET_BUILD_DIR}/$(basename "$lib")"
done

# Notifications are posted by the Alerts helpers, which macOS labels with their
# own name and icon; brand them as Stone.
icon="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/AppIcon.icns"
for helper in "$dst/${STONE_CORE_FRAMEWORK}.framework"/Versions/Current/Helpers/*Alerts*.app(N); do
  res="$helper/Contents/Resources"
  plutil -replace CFBundleDisplayName -string "Stone" "$res/base.lproj/InfoPlist.strings"
  plutil -replace CFBundleDisplayName -string "Stone" "$helper/Contents/Info.plist"
  [[ -f "$icon" ]] && cp "$icon" "$res/app.icns"
  codesign -f -s - --preserve-metadata=identifier,entitlements,flags "$helper" 2>/dev/null
done
