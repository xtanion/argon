# Building and developing Argon

Argon is two halves that build separately:

- **ArgonCore**: our Chromium-side code in `core/`, compiled into Chromium's
  framework from a plain Chromium checkout.
- **Argon.app**: the Swift/AppKit app in `app/`, an Xcode project that links that
  framework.

## Requirements

- macOS 13+ (developed on macOS 27, Apple Silicon)
- Xcode 26+ and the Metal toolchain: `xcodebuild -downloadComponent MetalToolchain`
- [depot_tools](https://commondatastorage.googleapis.com/chrome-infra-docs/flat/depot_tools/docs/html/depot_tools_tutorial.html)
  at `~/depot_tools`
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- About 100 GB of free disk for the checkout and build output

## 1. Chromium checkout (once)

Argon is pinned to Chromium **157.0.8103.38**.

```sh
mkdir -p ~/chromium && cd ~/chromium
cat > .gclient <<'GCLIENT'
solutions = [{
  "name": "src",
  "url": "https://chromium.googlesource.com/chromium/src.git@refs/tags/157.0.8103.38",
  "managed": False,
  "custom_deps": {},
  "custom_vars": {"checkout_nacl": False},
}]
target_os = ["mac"]
GCLIENT
PATH=$HOME/depot_tools:$PATH gclient sync --no-history
```

## 2. Wire ArgonCore into the checkout (once)

```sh
cd ~/chromium/src
ln -s ~/argon/core argon_core
git apply ~/argon/patches/argon/embedder-hooks.patch
```

`embedder-hooks.patch` holds the small Chromium changes Argon needs. See
[Embedder patch](#embedder-patch) below.

Create the build directory with `gn args out/Core`:

```gn
is_debug = false
is_component_build = true
symbol_level = 0
blink_symbol_level = 0
v8_symbol_level = 0
chrome_pgo_phase = 0
treat_warnings_as_errors = false
target_cpu = "arm64"
```

## 3. Build

```sh
# ArgonCore (inside Chromium's framework)
cd ~/chromium/src
PATH=$HOME/depot_tools:$PATH gn check out/Core '//argon_core/*'
PATH=$HOME/depot_tools:$PATH autoninja -C out/Core chrome

# Argon.app
cd ~/argon/app
xcodegen generate          # after adding files or editing project.yml
xcodebuild -project Argon.xcodeproj -scheme Argon -configuration Debug \
  -derivedDataPath build build

open build/Build/Products/Debug/Argon.app
```

The **Embed ArgonCore** build phase (`app/scripts/embed_core.sh`) copies
`Chromium Framework.framework` into the app. In component builds it also
symlinks `out/Core/*.dylib` next to the app, so Chromium's helper processes can
find their libraries.

## Day-to-day loop

| Changed | Rebuild |
| --- | --- |
| `core/**` | `autoninja -C out/Core chrome`, then `xcodebuild` (re-embeds the framework) |
| `core/public/*.h` (API used by Swift) | both of the above |
| `app/Sources/*.swift` | `xcodebuild` only |
| New Swift file or `project.yml` | `xcodegen generate`, then `xcodebuild` |
| Chromium file covered by the embedder patch | `autoninja`, then re-export the patch (below) |

Restart the app after rebuilding:

```sh
pkill -TERM -f "Argon.app/Contents/MacOS/Argon"
open ~/argon/app/build/Build/Products/Debug/Argon.app
```

### Logging

Chromium switches pass straight through, for example:

```sh
open app/build/Build/Products/Debug/Argon.app --stderr /tmp/argon.log --args \
  --enable-logging=stderr --vmodule='*webauthn*=2,*permission*=1'
```

Crash reports land in `~/Library/Logs/DiagnosticReports/Argon-*.ips`.

## Embedder patch

Chromium assumes its own browser windows exist. These changes let Argon host
Chromium without them. All of them are in `patches/argon/embedder-hooks.patch`:

- `chrome/app`: `ChromeMainWithDelegate` and
  `ChromeMainDelegate::CreateChromeContentBrowserClient`, so Argon supplies its
  own main delegate and browser client.
- `chrome/BUILD.gn`: compiles `//argon_core` into `chrome_dll`.
- `chrome/browser/ui/tab_helpers.h`: lets `argon_core::ACTabHost` attach Chrome's
  tab helpers.
- `--argon-embedder` switch (added by `ACMain`): skips the profile picker and the
  post-install extension bubble, which both need a Chromium window.
- `components/web_modal`, `components/constrained_window`,
  `ui/views/widget/native_widget_mac.mm`: tab-modal dialogs (passkeys, HTTP auth,
  and others) over a plain AppKit view.
- `chrome/browser/app_controller_mac.mm`: tolerates a main menu with no Bookmarks
  menu.
- `chrome/browser/ui/cocoa/renderer_context_menu`, `ui/views/controls/menu`:
  page context menus without a views widget.
- `chrome/browser/devtools`: DevTools docks inside Argon's tab view, and Argon
  tabs count as DevTools "page" targets.

After changing any of those files, re-export the patch:

```sh
cd ~/chromium/src
git diff -- chrome/app chrome/BUILD.gn chrome/browser/ui/tab_helpers.h \
  chrome/browser/ui/views/profiles/profile_picker_view.cc \
  components/constrained_window components/web_modal \
  ui/views/widget/native_widget_mac.mm chrome/browser/app_controller_mac.mm \
  chrome/browser/ui/extensions/extension_install_ui_desktop.cc \
  ui/views/controls/menu chrome/browser/ui/cocoa/renderer_context_menu \
  chrome/browser/devtools > ~/argon/patches/argon/embedder-hooks.patch
```

## Conventions

- `core/public` is the only API Swift sees. Classes use the `AC` prefix, with
  Swift names given by `NS_SWIFT_NAME` (`ACTab` becomes `Tab`).
- New Chromium-side code goes in `core/` (never a Chromium patch) unless it must
  change Chromium's own behaviour.
- Never push to `imputnet/*`. Personal work goes to the `xtanion` remote.
