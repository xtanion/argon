# Building and developing Stone

Stone is two halves that build separately:

- **StoneCore**: our Chromium-side code in `core/`, compiled into Chromium's
  framework from a plain Chromium checkout.
- **Stone.app**: the Swift/AppKit app in `app/`, an Xcode project that links that
  framework.

## Requirements

- macOS 13+ (developed on macOS 27, Apple Silicon)
- Xcode 26+ and the Metal toolchain: `xcodebuild -downloadComponent MetalToolchain`
- [depot_tools](https://commondatastorage.googleapis.com/chrome-infra-docs/flat/depot_tools/docs/html/depot_tools_tutorial.html)
  at `~/depot_tools`
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- About 100 GB of free disk for the checkout and build output

## 1. Chromium checkout (once)

Stone is pinned to Chromium **157.0.8103.38**.

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

## 2. Wire StoneCore into the checkout (once)

```sh
cd ~/chromium/src
ln -s ~/stone/core stone_core
git apply ~/stone/patches/stone/embedder-hooks.patch
```

`embedder-hooks.patch` holds the small Chromium changes Stone needs. See
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
# StoneCore (inside Chromium's framework)
cd ~/chromium/src
PATH=$HOME/depot_tools:$PATH gn check out/Core '//stone_core/*'
PATH=$HOME/depot_tools:$PATH autoninja -C out/Core chrome

# Stone.app
cd ~/stone/app
xcodegen generate          # after adding files or editing project.yml
xcodebuild -project Stone.xcodeproj -scheme Stone -configuration Debug \
  -derivedDataPath build build

open build/Build/Products/Debug/Stone.app
```

The **Embed StoneCore** build phase (`app/scripts/embed_core.sh`) copies
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
pkill -TERM -f "Stone.app/Contents/MacOS/Stone"
open ~/stone/app/build/Build/Products/Debug/Stone.app
```

### Logging

Chromium switches pass straight through, for example:

```sh
open app/build/Build/Products/Debug/Stone.app --stderr /tmp/stone.log --args \
  --enable-logging=stderr --vmodule='*webauthn*=2,*permission*=1'
```

Crash reports land in `~/Library/Logs/DiagnosticReports/Stone-*.ips`.

## Embedder patch

Chromium assumes its own browser windows exist. These changes let Stone host
Chromium without them. All of them are in `patches/stone/embedder-hooks.patch`:

- `chrome/app`: `ChromeMainWithDelegate` and
  `ChromeMainDelegate::CreateChromeContentBrowserClient`, so Stone supplies its
  own main delegate and browser client.
- `chrome/BUILD.gn`: compiles `//stone_core` into `chrome_dll`.
- `chrome/browser/ui/tab_helpers.h`: lets `stone_core::STTabHost` attach Chrome's
  tab helpers.
- `--stone-embedder` switch (added by `STMain`): skips the profile picker and the
  post-install extension bubble, which both need a Chromium window.
- `components/web_modal`, `components/constrained_window`,
  `ui/views/widget/native_widget_mac.mm`: tab-modal dialogs (passkeys, HTTP auth,
  and others) over a plain AppKit view.
- `chrome/browser/app_controller_mac.mm`: tolerates a main menu with no Bookmarks
  menu.
- `chrome/browser/ui/cocoa/renderer_context_menu`, `ui/views/controls/menu`:
  page context menus without a views widget.
- `chrome/browser/devtools`: DevTools docks inside Stone's tab view, and Stone
  tabs count as DevTools "page" targets.
- `chrome/browser/extensions/api/tabs`, `extension_tab_util`: Stone's tabs and
  spaces reach `chrome.tabs` and `chrome.windows`. `ExternalTabsDelegate` lists
  the tabs, `TabsEventRouter::OnExternalTab*` fires `onCreated`, `onActivated`
  and `onRemoved` (and tracks them for `onUpdated`), and `windows_api.cc` accepts
  `WindowController`s with no `BrowserWindowInterface` whose type is `normal`.
- `chrome/browser/ui/views/overlay`: the picture in picture window's top bar in
  Stone's style (back to tab on the left, minimize and close on the right, SF
  Symbols). `stone_symbol.h` and `stone_symbol_mac.mm` are new files, so mark
  them with `git add -N` before exporting.

After changing any of those files, re-export the patch:

```sh
cd ~/chromium/src
git diff -- chrome/app chrome/BUILD.gn chrome/browser/ui/tab_helpers.h \
  chrome/browser/ui/views/profiles/profile_picker_view.cc \
  components/constrained_window components/web_modal \
  ui/views/widget/native_widget_mac.mm chrome/browser/app_controller_mac.mm \
  chrome/browser/ui/extensions/extension_install_ui_desktop.cc \
  ui/views/controls/menu chrome/browser/ui/cocoa/renderer_context_menu \
  chrome/browser/devtools chrome/browser/ui/views/overlay \
  chrome/browser/extensions/api/tabs chrome/browser/extensions/extension_tab_util.cc \
  chrome/browser/extensions/extension_tab_util.h \
  chrome/browser/ui/passwords/passwords_client_ui_delegate.cc \
  chrome/browser/ui/passwords/passwords_client_ui_delegate.h \
  > ~/stone/patches/stone/embedder-hooks.patch
```

## Conventions

- `core/public` is the only API Swift sees. Classes use the `AC` prefix, with
  Swift names given by `NS_SWIFT_NAME` (`STTab` becomes `Tab`).
- New Chromium-side code goes in `core/` (never a Chromium patch) unless it must
  change Chromium's own behaviour.
- Never push to `imputnet/*`. Personal work goes to the `xtanion` remote.
