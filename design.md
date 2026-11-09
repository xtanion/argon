# Argon: Design Reference

The source of truth for Argon's Arc-inspired look. Check this file before adding
or restyling anything, and update it when a value changes.

These values were first built as a Chromium Views patch for Helium
(`patches/helium/ui/layout/arc-sidebar.patch` and `chrome/browser/ui/views/helium/*`,
now archived on the `views-arc-ui` branch). The code paths and class names below
point at that archived implementation. The native app in `app/Sources` reproduces
the same measurements, colours and motion in AppKit (`Theme.swift`,
`SidebarView.swift`, `Controls.swift`).

## Principles

- **Arc, not Chrome.** Sidebar-first, quiet chrome, content framed as a rounded card.
- **Minimal by default.** Controls appear on hover or focus rather than always. Separators are hairlines that never run edge to edge.
- **One highlight at a time.** Only one sidebar item looks active. While the command bar is open, the New Tab row has the highlight and the real active tab does not.
- **Gentle motion.** Short, springy, and never in the way. Honour `gfx::Animation::ShouldRenderRichAnimation()`, so reduced motion means no animation.
- **Modular.** Reusable pieces go in `chrome/browser/ui/views/helium/<module>/`, each with its own `BUILD.gn` source_set. Don't inline one-off copies.
- **Code style.** No emojis, minimal comments, and English strings are hardcoded for now (localisation pending).

## Layout

| Token | Value | Where |
|---|---|---|
| Sidebar default width | 260 (upstream 200) | `vertical_tab_strip_state.h` `kVerticalTabStripDefaultUncollapsedWidth` |
| Sidebar horizontal padding | 8 (6) | `layout_constants.cc` `kVerticalTabStripHorizontalPadding` |
| Tab / favourite tile height | 36 / 46 (30) | `kVerticalTabHeight`, `kVerticalTabPinnedHeight` |
| New tab button size | 36 (32) | `kVerticalTabStripNewTabButtonSize` |
| Corner radius (tabs, favourites, New Tab highlight, URL pill) | 12 (best circular fit to Arc's continuous corner) | `kVerticalTabCornerRadius`, `kSidebarCornerRadius` |
| Corner radius (toolbar, main region) | 10 (8) | `kToolbarCornerRadius`, `kMainBackgroundRegionCornerRadius` |
| Page card inset | 8 | `frame_corner_radius.h` `kRoundedFrameInset` |
| Generic frame radius | 10 (8) | `frame_corner_radius.cc` |
| Inner frame radius | `max(generic, systemWindowRadius - 8)` | `frame_corner_radius.cc` |

### Sidebar structure (top to bottom)

The sidebar toolbar layout (`ShouldUseSidebarToolbar`) also applies in macOS fullscreen whenever the toolbar is visible; Helium's fullscreen draws its own traffic lights in the leading exclusion. Content fullscreen (video) hides the toolbar and so falls back.

1. **First row:** traffic lights, then the sidebar toggle on the left; back, forward and reload on the right. The row is `kSidebarTitlebarHeight` (46) tall (`ToolbarView::GetSidebarFirstRowHeight`). The window titlebar takes the same height, so macOS centres the traffic lights on the row at about 23pt (Arc measures 23.75).
2. **URL pill:** the location bar, full width minus 2 x padding, `kVerticalTabHeight` (36) tall, directly below the first row (top at 46, matching Arc).
   - No location or site icon. The text starts 10pt from the pill edge, matching the ~10pt padding around the trailing icons (`kSidebarUrlTextExtraInset` = 0).
   - Page action icons (bookmark star etc.) are hidden in the sidebar.
   - Copy Link and Site Settings buttons (`helium/location_bar/url_hover_actions`) fade in on hover, fading in over 120 ms and out over 160 ms (`helium::animations::HoverReveal`).
3. **Pinned tabs container.**
4. **New Tab row:** a `HairlineSeparator` (inset 10) sits 10 above it, and both are wrapped in one section view. The section is placed after the pinned container, full width minus 2 x padding, then padding (`tab_strip_view_layout.cc`). It is excluded from the window-caption drag area.
5. **Unpinned tabs.** New tabs from the command bar open at the top of this group (`IndexOfFirstNonPinnedTab`).
6. **Bottom container:** the collapsed-mode new tab button only. There is no theme button; theme editing lives in the right-click menu.

- **Double-click** on empty sidebar space opens the command bar instead of zooming the window (`BrowserView::HandleDraggableAreaDoubleClick`, through the NSWindow `draggableAreaDoubleClickHandler`).

### URL editor (`helium/location_bar/url_editor`)

- A left press on the sidebar URL pill, or Cmd+L, opens the command bar in `CommandBarOptions::Mode::kEditUrl` instead of editing the pill in place. Presses on the hover actions pass through.
- **Look:** pinned over the pill (`TOP_LEFT`, 6 overhang), 480 wide (clamped to the window), 52 field row with the page favicon, the full URL selected and a trailing info button for Site Information. No separator under the field.
- **Rows:** the current page first (selected, no "Switch to Tab"), then up to 4 other tabs in MRU order. Typing switches to autocomplete results.
- **Enter:** switches to an already open tab with that URL, otherwise navigates the current tab.

### Empty window (`chrome/browser/ui/helium/placeholder_tab`)

- Closing the last tab keeps the window open, as in Arc. Both close paths (`TabStripModel::ExecuteCloseTabs`, `BrowserTabStripModelDelegate::CloseTab`) add a new tab page and mark it as the placeholder. The `close-window-with-last-tab=always` switch opts out.
- The placeholder's sidebar row is hidden and takes no height (`TabView::helium_placeholder_`).
- A window that opens on a lone new tab page (startup, a new window) marks it as the placeholder too (`MarkPlaceholderTabIfEmpty` in `TabStripModel::InsertTabAtImpl`).
- The placeholder shows a blank page in a panel grey (white `0x2A` over a dark frame) via a small `data:` page, never the new tab page; the URL pill shows the empty hint for it (`BrowserLocationBarModelDelegate::ShouldDisplayURL`).
- Programmatic focus never reaches the sidebar pill, so the omnibox popup can't open under the URL editor.
- It becomes a normal tab on its first real navigation, and closes itself when it is hidden and no longer active, for example after a new tab opens.
- Closing the placeholder itself (Cmd+W in an empty window) closes the window.
- **Pill:** while the omnibox text is empty the pill shows `EmptyUrlHint` (search glyph, "Search or Enter URL...", `kColorSysOnSurfaceSubtle`). On the placeholder the URL editor opens with an empty field and the search glyph.

### Hidden sidebar (Arc "hide sidebar")

- **Toggle:** Cmd+S or the sidebar button, whenever the sidebar toolbar layout is in use (`BrowserView::ToggleHeliumSidebarHidden`). This replaces collapse-to-icons in that layout.
- **Resizing:** the sidebar never drags below 190 (`kSidebarMinWidth`). Dragging 40 further (`kSidebarHideDragDistance`) hides it as Cmd+S does, instead of collapsing to icons. When the toolbar row is too narrow for the toggle plus the nav buttons, the toggle drops out first.
- **Hidden:** built on Zen mode with both halves unpinned. The whole sidebar, toolbar included, slides out, leaving only the page.
- **Traffic lights:** in hidden mode they ride on the card instead of fading. `BrowserFrameViewMac::SetCaptionButtonsOpacity` translates the buttons' titlebar container layer by `-(1 - reveal) * (card width + kSidebarFloatingInset)`. It uses a layer transform because moving the container's bounds makes AppKit re-lay the buttons out against the shifted origin, leaving them displaced. The buttons stay fully opaque until the reveal reaches 0; without a layer they fall back to fading. Outside hidden mode they still fade with the top chrome.
- **Borders:** only the floating card has an outline (`kColorToolbarContentAreaSeparator`, from `SetFloatingStyleForLayout`). The web contents has no outline or 1px inset when it is not split (`ContentsContainerView::UpdateBorderAndOverlay`), as in Arc; split view keeps its outlines.
- **Hidden card toolbar:** while hidden, the top container is layered and ordered above the floating card, and both the top container and toolbar backgrounds are dropped, so the card shows through with all toolbar buttons at full size, as in Arc.
- **Reveal:** pointer at the left edge. The sidebar returns as a floating card inset `kSidebarFloatingInset` (8) from the window, with the toolbar on top of the card. The toolbar stays at the window top so its row lines up with the traffic lights; the card's interior top margin covers it. The top container is raised above the strip while hidden.
- Top and side reveal are tied together while hidden, and the top-edge trigger is ignored.

## Typography

- **All sidebar text (tab titles, New Tab row, URL pill):** 13 pt SF Pro Regular (`kSidebarFontWeight`), from `helium::style::SidebarFontList()` in `helium/style/sidebar_style.h`. Change `kSidebarFontSize` there, never per view.
- **Sidebar icon frames:** every sidebar icon sits in a 24x24 frame (`kSidebarIconFrameSize`).
  - Vector icons use a 24 canvas with built-in padding and are drawn at the full 24.
  - The New Tab plus glyph is 12 wide by 12.5 tall (`arc_add`).
  - Link and site-settings glyphs are about 13 px.
  - Tab favicons are 16x16 (`kSidebarFaviconSize`) centred in a 20 slot that starts 7 into the tab, with a 5 gap to the title (title at window x 44, as Arc).
  - Favourite tiles show an 18x18 favicon (`kSidebarFavoriteIconSize`).
  - The New Tab row uses a 5 inset and 3 label gap, so the plus centres on the favicon column and the label lines up with the titles.
- **Tab spacing:** 5 between unpinned tabs (`kSidebarTabSpacing`, 41 pitch).
- **Favourites grid:** pinned tabs form a grid of up to 4 columns (`kSidebarFavoriteColumns`) with 9 gaps (`kSidebarFavoriteGap`). Inactive tiles use the pill fill (`kColorLocationBarBackground`) and blend toward the active fill on hover.
- **URL pill buttons:** 28 frames (`kSidebarPillIconSize`). They fade in while the pointer is anywhere in the sidebar column (`HoverReveal` with `RevealZone::kParentColumn`), as in Arc.
- **URL text:** the domain only (`BrowserLocationBarModelDelegate::ShouldTrimDisplayUrlAfterHostName` returns true with vertical tabs). The full URL shows in the URL editor.
- **Toolbar row:** the sidebar toggle sits 7 left of the traffic-light inset (`kSidebarToggleShift`); back, forward and reload have 2 extra between them (`kSidebarNavButtonSpacing`), a 34 pitch.
- **Traffic lights:** 13 from the window edge (`_minXTitlebarWidgetInset` in `browser_native_widget_window_mac.mm`), as Arc.
- **Empty URL hint:** search glyph 12 in from the pill edge, 11 gap to "Search or Enter URL...", as Arc.
- **URL pill focus ring:** never drawn in sidebar style; editing happens in the URL editor popup.
- **Toolbar icons:** the sidebar toggle (`arc_sidebar`, a 3-radius frame with three short rounded lines) is a 20 icon, back/forward/reload are 22 (`kSidebarNavIconSize`, via `ToolbarButton::SetIconSizeOverride`), all in 32 boxes (`kSidebarToolbarButtonSize`). Icons use the frame foreground at `0x99`. The nav group sits 4 closer to the sidebar edge (`kSidebarNavTrailingInset`).
- **Icon button hover shape:** every sidebar icon button (toolbar, URL pill, tab close) uses one rounded square with a 6 radius (`kSidebarButtonCornerRadius`, `helium/style/sidebar_button.h`).
- **URL pill:** also 13 pt, text white at `0xC8` over a dark frame, via `LocationBarView::SetSidebarStyle`.
- **Command bar field:** default font +6.
- **Command bar row title:** +1, medium weight. The subtitle uses the secondary colour at default size.
- **"Switch to Tab" label:** medium weight.

## Colour

- **Ink dark frame:** `#141416`, used when the colour mode is dark and there is no custom theme or accent (`GetHeliumFrameColor`).
- **Accent theme:** the user's accent colour becomes the frame colour directly.
- **Surface** (URL pill, `kColorToolbarBackgroundSubtleEmphasis`, `kColorLocationBarBackground`), derived from the frame colour by `GetHeliumSurfaceColor`:
  - luminance < 0.18: white blended at alpha `0x1D` (Arc pill #2B2C2C on #101010);
  - luminance > 0.85: black blended at alpha `0x10`;
  - otherwise: white blended at alpha `0x99`.
- **Toolbar:** follows `kColorFrameActive` whenever a Helium frame colour is active, so the sidebar and toolbar are a single surface.
- **Custom themes and high contrast** skip all Helium overrides.

### Translucency scale (alpha on the foreground colour)

| Use | Alpha |
|---|---|
| Hairline separator | `0x1F` (`0x24` above New Tab, 11 gap) |
| Unselected arrow box (command bar) | `0x14` |
| Selected row background (command bar) | `0x1A` |
| Swatch outline ring | `0x33` |
| Swatch hover halo | `0x66` |

## Iconography

- **Grid:** toolbar icons use a 20x20 canvas with stroke 1.5, round geometry and Figma-matched. Sidebar icons use a 24x24 canvas with stroke 1.5 and inner padding. Files are `components/vector_icons/arc_*.icon`.
- **24-grid icons:** `arc_add`, `arc_link`, `arc_site_settings`.
- **Icon set:** `arc_back`, `arc_forward`, `arc_reload`, `arc_sidebar`, `arc_add`, `arc_palette`, `arc_search` (circle 9,9 r5.5 plus a handle from 13,13 to 16.5,16.5), `arc_globe` (command bar page fallback), `arc_info` (URL editor Site Information).
- **Tab alert icons** (`tabs::GetAlertIcon` in `tab_alert_icon.cc`, shared by the sidebar, hover card and split-view mini toolbar): 20 grid, stroke 1.5, drawn at 16 (`kTabAlertIndicatorIconWidth`).
  - `arc_volume_up`: a filled speaker (rounded back, 0.75-radius cone tips) with two stroked waves (r3 and r6 around 10.75,10). `arc_volume_off`: the same speaker with a 4.25 X.
  - `arc_record` (all recording and desktop capture): r6.25 ring with a filled r3.25 dot. `arc_capture`: rounded screen (radius 2.5) with a filled dot. `arc_picture_in_picture`: the same screen with a filled inset window at the bottom right.
  - `arc_bluetooth` (connected and scanning), `arc_usb`, `arc_gamepad` (HID), `arc_serial`, `arc_vr`.
  - Glic and actor alerts keep their upstream icons.
- **New icons** must use the same canvas and stroke. Register them in `components/vector_icons/BUILD.gn`.
- **Sizes:** 16 in rows and menus; 18 for the command bar search glyph.

## Components

### Vertical tab

- **Close button:** shown only on hover or focus, including on the active tab (`tab_view_vertical_layout.cc`). The glyph is `arc_close` (24 canvas, stroke 1.5, 10 across) in a 24 frame at foreground alpha `kSidebarCloseIconAlpha` (`0x99`), via `TabCloseButton::SetSidebarStyle`.
- **Fills on Helium frames** (`GetHeliumTabColor`): on dark frames active is white at `0x31` and hover white at `0x1A`; on light frames active is white at `0xCC` and hover white at `0x66`. Hover is about half of active, as in Arc (Arc dark measures #121212 background, #2A2A2B hover, #404142 active).
- **Text:** every tab title uses the active foreground, whether active or not.
- **Sidebar button hover:** `kColorTabStripControlButtonInkDrop*` follow the tab hover and active fills on Helium frames, so the New Tab row never picks up the accent tint.
- **Active highlight:** can be suppressed (`TabView::SetActiveHighlightSuppressed`), and the style delegate reads `ShouldPaintAsActive()`.
- **Animation:** press bounce, vertical orientation only, with a subtler style than the default (press 0.985, overshoot 1.005, 80/100/150ms) to match Arc.

### New Tab row (`VerticalNewTabButton`)

- **Idle:** foreground `kColorNewTabButtonCRForegroundFrameActive`, overridden to the frame's foreground at `0x8A` (Arc #919191 on dark).
- **Highlighted** (command bar open):
  - foreground `kColorTabForegroundActiveFrameActive`;
  - background `kColorTabBackgroundActiveFrameActive`;
  - a rounded rect at the tab corner radius, so it looks exactly like an active tab.
- **Animation:** press bounce.

### Command bar (`helium/command_bar/`), Arc's Spotlight-style new tab

- **Bubble:** centred on the window, `TOP_CENTER`, no margins, corner radius 10.
- **Width:** 40% of the window, clamped to 560-800. The top sits at 34% of the window height (Arc: 766 wide on a 1920 window).
- **Header:** 62 high, 20 horizontal inset. Search glyph, then a borderless field with the placeholder `Search or Enter URL...`.
- **Divider:** `HairlineSeparator` between the header and the results.
- **Results:** 6 top and 7 side/bottom insets, 4 between rows; at most 6 autocomplete rows, or 4 open-tab rows when the query is empty.
- **Row** (`CommandBarRow`):
  - 46 high, 12 horizontal inset, 12 gap, radius 6;
  - title at most 320 wide when it has a subtitle.
- **Switch to Tab:** a label plus a 24x24 arrow box (radius 6, 14px arrow).
  - Selected: the box is filled with the foreground colour and the arrow uses `kColorSysSurface`.
  - Unselected: the box is filled at alpha `0x14`.
- **Keys:** Up/Down to move, Enter to open or switch, Esc to close. Enter with no rows opens a plain new tab.
- **Availability:** normal windows with the vertical sidebar visible, not in fullscreen. Otherwise Cmd+T falls back to a normal new tab.

### Tab switcher (`helium/tab_switcher/`), Ctrl+Tab in most-recently-used order

- **Order:** the active tab first, then by last-active time (`helium::GetTabsInMruOrder`). At most 10 tabs.
- **Quick tap:** releasing Ctrl within 150 ms switches straight to the previous tab, with no panel.
- **Holding Ctrl:** a 440-wide panel appears centred over the page, with rows matching the command bar's. Each Tab moves forward and Shift+Tab moves back; releasing Ctrl switches.
- **Focus:** the panel never takes focus. Ctrl is polled every 30 ms (`IsControlKeyDown`, which reads `NSEvent.modifierFlags` on mac).
- **Mouse:** clicking a row switches to it; hovering a row selects it.
- **Wiring:** hooked into `IDC_CYCLE_TO_NEXT_TAB`/`IDC_CYCLE_TO_PREV_TAB` through `BrowserView::CycleHeliumTabSwitcher`.

### Open-tab reuse (`chrome/browser/ui/helium/tab_lookup`)

- **Matching:** opening a URL that is already open switches to that tab instead of duplicating it.
  - The fragment is ignored, and http and https count as the same page.
  - The check runs against the current window only.
- **Where it applies:** command bar entries and links opened from other apps (`StartupBrowserCreatorImpl`, not at process startup).

### Spaces (`helium/spaces/`, `chrome/browser/ui/helium/space_title`)

Arc-style spaces inside one window: each space is its own tab list, switched without changing windows.

- **Model:** a space is a tab group shown through Chrome's tab group focus mode (`kTabGroupsFocusing`, enabled; focus freezing off so background spaces keep running). Only the focused group's tabs are listed. Pinned tabs stay global, like Arc's favorites.
- **Identity:** the space's icon and name are stored in the group title behind private-use markers (`U+E000 icon U+E001 name`, `MakeSpaceTitle`/`ParseSpaceTitle`). Group ids change on session restore and window reopen, the title does not.
- **Controller (`SpacesController`, owned by the sidebar region view):**
  - Creates "Space 1" when a window has none; moves any tab that lands outside a space into the active one.
  - Re-enters focus whenever it drops, preferring the active tab's space, so activating a tab from another space (tab search, links) switches to that space.
  - Remembers the last active tab per space and restores it on switch.
- **Empty spaces:** a space keeps a hidden placeholder tab when its last tab closes (`KeepSpacesAfterClosing` in `TabStripModel::ExecuteCloseTabs`). The placeholder does not self-close while it is the only tab in its group, and restored placeholders are re-marked from their blank-page URL.
- **Space bar (`SpaceBarView`):** 40 high at the bottom of the sidebar. Space icons (28 buttons, 18 glyph, 6 apart) centred; New Space (+) on the right. Active space uses `kColorSysOnSurface`, others `kColorToolbarButtonIcon`. Right-click: Edit Space, Delete Space.
- **Editor (`SpaceEditorBubble`):** name field above an 8-column grid of the 40 space glyphs; changes apply live. Opens after creating a space.
- **Switching:** click, Ctrl+1..9, or a two-finger horizontal swipe on the sidebar (`VerticalTabStripFocusSwipeController` rotates spaces, no wrap). The tab list slides in from the swipe direction (28, 220ms, ease-out) and fades in.
- **Group chrome:** space groups have no header, unfocus row or group line in the vertical strip, and do not tint the window (`UpdateFocusModeTheme` skips them).
- **Glyphs:** `components/vector_icons/helium_space_*.icon`, a 20 canvas with 1.5 strokes, round caps; registry in `space_icons.cc`.

### Hairline separator (`helium/controls/`)

- `HairlineSeparator(inset = 16, alpha = 0x1F)`: a 0-width (1 device pixel) stroke in `kColorSysOnSurface`, inset on both ends.

### Theme picker (`VerticalThemePickerBubble`)

- **Swatches:** 40 in 8 columns. Each is 26 in size with 6 spacing, with an outline ring and a hover/selected halo.
- **Palette rows:** whites, pastels, muted mids, deep tones, near-blacks.
- **Margins and footer:** margins 4/16/16/16 (TLBR). The footer has a 6 top inset, a hex field 8 characters wide, and Reset.
- **Applying a colour:** sets the user colour as an accent, plus dark or light mode from the colour's darkness. Reset returns to the system scheme.
- **Opening:** opened from the sidebar right-click menu and anchored at the click point.

### Sidebar context menu (`VerticalSidebarContextMenu`)

- **Where:** right-click on empty sidebar space. Tabs and buttons keep their own menus.
- **Items:** New Tab, a separator, then Edit Theme...
- **Icons:** set, but macOS native menus don't draw them.

## Motion (`helium/animations/`)

| Style | Value |
|---|---|
| Press scale | 0.97 |
| Overshoot scale | 1.012 |
| Press-in | 90 ms, ease-out |
| Overshoot | 110 ms, ease-out |
| Settle | 170 ms, ease-in-out |

- **Defaults vs tabs:** the table is the default `BounceStyle` (New Tab row, command bar rows). Vertical tabs pass a subtler style (press 0.985, overshoot 1.005, 80/100/150 ms) because a 3% shrink on a ~220 wide tab moves its edges ~7px, much more than Arc.
- Scale pivots on the view's centre. Preemption is `IMMEDIATELY_ANIMATE_TO_NEW_TARGET`, so rapid clicks never stack.
- **API:**
  - `AnimatePressIn` and `AnimateRelease` for held presses;
  - `PlayBounce` for programmatic activation;
  - `PressBounce` attaches the behaviour to any view with one member (mouse and gesture).
- **Layer guard:** code that destroys layers after its own animations must check `helium::animations::IsBouncing(view)` first. This is already done in the tab layout manager and the drag handler.
- **Reuse:** new animations go in this module with a `*Style` struct of tunables and defaults matching the table above.

## Known gaps

- The hex field shows a `#RRGGBB` placeholder instead of the current colour.
- No inline autocomplete in the command bar. No open/close animation for the command bar.
- Not built yet: "Clear" button, space name row.
- Spaces: the swipe triggers at a threshold rather than tracking the fingers; spaces are per window (Arc shares them across windows); no per-space profile or colour (every space shares the window's Chromium profile, so cookies, logins, history and extensions are shared; Arc instead lets each space be tied to its own Chromium profile, and one window cannot hold tabs from two profiles without deep changes); the space editor bubble widget is destroyed as soon as it closes, because a closed client-owned bubble stays registered for parent theme changes and crashed the focus-mode theme refresh on switch; with horizontal tabs only the active space's tabs show and there is no switcher; tab context menu group items can still move a tab out of its space (it is pulled back into the active space).
- The sidebar URL pill hides the security indicator ("Not secure" chip); Site Settings is the way in.
- Strings are not localised.
- Links opened from other apps land at the bottom of the tab list, not the top as in Arc.
- Open-tab reuse covers the command bar and external links only; links clicked inside a page still open duplicates.
- The empty URL hint glyph starts at 12 while typed URL text starts at 10.
- The default favicon for pages without one is still the upstream raster globe (`favicon::GetDefaultFaviconModel`), not `arc_globe`.
