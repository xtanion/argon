# Argon: plan

Goal: an Arc-style browser for macOS. Our own native app (Swift + AppKit) owns the
whole interface; Chromium provides the engine and Chrome's back-end services.
It must be at least as fast as Helium (the Chromium browser this grew out of) and
feel native.

Why: Chromium's window layer ties one window to one profile. Arc-style spaces need
tabs from several profiles in one window, plus interface polish that keeps fighting
Chromium's window code. Arc ships no Chromium window code at all (no `BrowserView`,
`ToolbarView`, `LocationBarView` in `ArcCore.framework`); it has its own
`arc/browser/` layer and a Swift app on top. We do the same.

## Decisions (defaults, change any time)

1. Interface: Swift + AppKit. SwiftUI only for small panels.
2. Build: the app is an Xcode project; Chromium's build compiles ArgonCore
   (`//argon_core`) into `Chromium Framework.framework`, which the app embeds.
3. The old Views-based Helium work is on the `views-arc-ui` branch of the private
   `xtanion/helium-macos` repo (remote `xtanion`): `archive/views-arc-ui/`
   (`arc-sidebar.patch`, `series.merged`, `design.md`) and `patches/helium/ui/`.
   `design.md` stays the interface spec.
4. Repo: everything lives in this repo (layout below). The Chromium checkout lives
   outside it at `~/chromium/src`.

## Layout

```
argon/
  plan.md
  design.md              interface spec (sidebar, spaces, address bar, motion)
  core/                  Chromium-side code, mapped into the checkout as //argon_core
    BUILD.gn
    app/                 startup, main parts, content client
    browser/             profiles, tabs, windows, delegates, prompts
    public/              Obj-C API (AC* classes) used by the Swift app
  app/                   Xcode project: Argon.app (Swift + AppKit)
  patches/argon/         Chromium changes Argon needs (embedder-hooks.patch)

~/chromium/src           Chromium git checkout, pinned to 157.0.8103.38
  argon_core -> ~/argon/core
  out/Core               build output (component build)
```

## Source

- Checkout: depot_tools, `.gclient` pinned to `refs/tags/157.0.8103.38`,
  `--no-history` to save disk. Today Argon runs on plain Chromium plus
  `patches/argon/embedder-hooks.patch`.
- Later: apply Helium's engine and privacy patches (ungoogled-chromium,
  helium/core and similar) with quilt, skipping ones that only touch
  `chrome/browser/ui/views`.
- `core/` is linked into the checkout, so our code is never a patch.

## Architecture

```
Argon.app (Swift, AppKit)
  sidebar, spaces, tab list, address bar, command bar, prompts, settings shell
        |  Obj-C API (core/public)
ArgonCore (//argon_core, inside Chromium Framework.framework)
  argon_core: ACApplication, ACProfile, ACTab, ACAutocomplete, ACDownload, delegates
  Chrome back-end services reused as-is: profiles, history, autocomplete, search
  engines, bookmarks, downloads, passwords, autofill, permissions, extensions,
  site settings, WebUI pages (settings, history, downloads, extensions)
  Chromium engine (content/, blink, net, gpu) + embedder hooks
```

- Startup reuses Chrome's main parts and content browser client; we override only
  what opens windows, tabs and dialogs.
- Each tab is a `WebContents` from its space's profile. Its view sits directly in
  an AppKit view (as `content_shell` does on Mac), so tabs from different profiles
  share a window naturally.
- Our windows implement `BrowserWindowInterface`
  (`chrome/browser/ui/browser_window/public/browser_window_interface.h`), so Chrome
  features that look for a window find ours. That includes the `chrome.tabs` and
  `chrome.windows` extension APIs.
- Prompts plug into existing interfaces, for example
  `components/permissions/permission_prompt.h`. Chrome keeps the logic and we draw
  the UI.

## Milestones

### M0: prototype and go/no-go (2-3 weeks)
- [x] depot_tools, Chromium checkout at 157.0.8103.38, first build of `chrome` to
      confirm the toolchain (`out/Core`: release, component, symbol_level 0)
- [x] `core/` skeleton: public Obj-C API (`ACMain`, `ACApplication`, `ACProfile`,
      `ACTab`), main delegate, browser client, main extra parts, tab host
- [x] `app/` skeleton: XcodeGen `project.yml`, Swift entry point, two-profile
      prototype window; type-checks under Swift 6
- [x] Verify the skeleton against the checkout: `ChromeMainDelegate` constructor
      and GN target, `ProfileManager::CreateProfileAsync`, `KeepAliveOrigin`,
      `ProfileKeepAliveOrigin`, `WebContentsDelegate` signatures, what
      `ChromeMain` does on Mac beyond `ContentMain`
- [x] `ACMain` ships inside Chrome's framework library (`chrome_dll`). Engine
      hook patch: `patches/argon/embedder-hooks.patch` adds
      `ChromeMainWithDelegate` and `ChromeMainDelegate::CreateChromeContentBrowserClient`.
      Non-component builds still need `_ACMain` and `_OBJC_CLASS_$_AC*` in
      `chrome/app/framework.exports`
- [x] Attach Chrome's tab helpers to our WebContents (autofill, permissions,
      favicons, and the rest Chrome adds in `TabHelpers`)
- [x] `core/` linked in; the app starts Chromium with Chrome's services (GPU,
      renderers, network, storage; both profiles created). Dev builds symlink
      `out/Core/*.dylib` next to the app so helpers resolve their rpaths
- [x] Minimal Swift app: one window, two tabs from two profiles side by side
- [ ] Measure against Helium: cold start, memory per tab, scroll frame
      times at 120 Hz, input delay
- [ ] Audit Chrome code that assumes a Chromium window (`BrowserList`,
      `FindBrowserWithTab`, `chrome::Navigate`). List what breaks or no-ops
- [x] Go: Argon is the daily driver; performance numbers still to be measured

### M1: bridge
- [x] Application, profiles, tabs
- [x] Tab events: navigation, title, favicon, loading, new tab and pop-up
      requests, close, page fullscreen
- [x] JS dialogs (app-modal), file pickers, eye dropper, page context menus
- [ ] Find in page, zoom
- [ ] `BrowserWindowInterface` and tab features on our windows (needed by
      extensions and by Chrome code that looks up a window)

### M2: usable for daily browsing
- [x] First Arc shell (`app/Sources`): tinted frame per space, sidebar with traffic
      lights on the 46pt row, nav buttons, URL pill, space title, New Tab row, tab
      list with favicons, space bar (icon, colour, rename, delete via right-click),
      rounded page card, command bar (new tab, edit URL, switch to open tabs),
      Cmd+S hide sidebar, sidebar resize, swipe between spaces, shortcuts, state
      saved and restored with lazily loaded tabs. Each space has its own profile
- Window with traffic lights, sidebar, spaces backed by profiles from the start
- [x] Address bar and command bar on Chrome's `AutocompleteController`
      (history, shortcuts, bookmarks, search suggestions, inline completion)
- [x] Profile picker disabled for the embedder (`--argon-embedder`)
- Tab list, favourites
- Command bar, shortcuts, swipe between spaces that follows the fingers

### M3: everyday prompts
- [x] Tab-modal dialog host (`ACTabHost` as `WebContentsModalDialogHost`):
      WebAuthn sheet (phone/QR, security keys), HTTP auth
- [x] Permission prompts (`ACPermissionPrompt` sheet), camera/mic requests
- [x] DevTools docked in the tab view, Inspect from the context menu
- [ ] Downloads panel (in progress)
- [ ] iCloud Keychain passkeys: needs Apple's
      `com.apple.developer.web-browser.public-key-credential` entitlement for
      `dev.argon.browser`
- Page info
- Print preview (WebUI dialog), PDF viewer (needs extensions, M5)
- Fullscreen video, picture-in-picture

### M4: passwords and autofill
- Native popups driven by Chrome's password manager and autofill

### M5: extensions
- Extension system and content scripts come for free
- `chrome.tabs` and `chrome.windows` through `BrowserWindowInterface`; bridge any gaps
- Toolbar actions and popups, extension context menus, side panel

### M6: around the browser
- Session restore, recently closed, history, settings (Chrome's WebUI), import
- Sparkle updates, crash reporting

### M7: polish and performance
- Motion, accessibility (VoiceOver, focus order), memory pressure and tab
  discarding, energy

## Performance and polish rules

- AppKit for the tab list, sidebar and address bar dropdown; SwiftUI only for
  small panels.
- Core Animation for every transition. Never relayout web content mid-animation;
  move layers or snapshots instead.
- Chromium's UI thread is the main thread: bridge calls stay cheap and never block.
- Budgets checked at every milestone: cold start, new-tab-to-typing, frame times
  during swipes, memory with 50 tabs. All must match or beat Helium.

## Risks

- Chrome code that silently needs a Chromium window: the M0 audit finds it early.
- Chromium updates: the bridge uses stable interfaces, but every bump needs a check,
  and security bumps must land fast.
- Extensions will not be 100%. The target is that popular extensions work fully.
