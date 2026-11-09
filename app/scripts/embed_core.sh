#!/bin/zsh
set -euo pipefail

src="${ARGON_CORE_OUT}/${ARGON_CORE_FRAMEWORK}.framework"
dst="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"

if [[ ! -d "$src" ]]; then
  echo "error: ${src} not found; build ArgonCore first" >&2
  exit 1
fi

mkdir -p "$dst"
rsync -a --delete "$src" "$dst/"

# Component builds: helpers find their dylibs relative to the app's parent
# directory, as Chromium.app does inside the out directory.
for lib in "${ARGON_CORE_OUT}"/*.dylib; do
  ln -sfn "$lib" "${TARGET_BUILD_DIR}/$(basename "$lib")"
done
