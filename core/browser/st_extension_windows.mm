// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#import "stone_core/browser/st_internal.h"

#import <AppKit/AppKit.h>

#include <map>
#include <memory>
#include <set>
#include <string>

#include "base/no_destructor.h"
#include "chrome/browser/extensions/api/tabs/tabs_event_router.h"
#include "chrome/browser/extensions/api/tabs/tabs_windows_api.h"
#include "chrome/browser/extensions/extension_tab_util.h"
#include "chrome/browser/extensions/window_controller.h"
#include "chrome/browser/extensions/window_controller_list.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/common/extensions/api/tabs.h"
#include "components/sessions/content/session_tab_helper.h"
#include "content/public/browser/web_contents.h"
#include "extensions/common/constants.h"
#include "net/base/apple/url_conversions.h"
#include "ui/base/base_window.h"
#include "ui/base/mojom/window_show_state.mojom.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "url/gurl.h"

namespace stone_core {

namespace {

bool g_tab_events_suspended = false;

id<STExtensionTabsDelegate> Delegate() {
  return STApplication.sharedApplication.extensionTabsDelegate;
}

NSMapTable<NSNumber*, id>* WindowKeys() {
  static NSMapTable<NSNumber*, id>* keys =
      [NSMapTable strongToWeakObjectsMapTable];
  return keys;
}

SessionID WindowIdFor(id key) {
  static NSMapTable<id, NSNumber*>* ids =
      [NSMapTable weakToStrongObjectsMapTable];
  NSNumber* known = [ids objectForKey:key];
  if (known) {
    return SessionID::FromSerializedValue(known.intValue);
  }
  SessionID fresh = SessionID::NewUnique();
  [ids setObject:@(fresh.id()) forKey:key];
  [WindowKeys() setObject:key forKey:@(fresh.id())];
  return fresh;
}

NSArray<STExtensionWindow*>* WindowsFor(Profile* profile) {
  id<STExtensionTabsDelegate> delegate = Delegate();
  STProfile* st_profile = profile ? ProfileFor(profile) : nil;
  if (!delegate || !st_profile) {
    return @[];
  }
  return [delegate extensionWindowsForProfile:st_profile];
}

STExtensionWindow* FindWindow(Profile* profile, int window_id) {
  for (STExtensionWindow* window in WindowsFor(profile)) {
    if (WindowIdFor(window.key).id() == window_id) {
      return window;
    }
  }
  return nil;
}

// Tab ids come from SessionTabHelper, whose window id has to match the
// controller's for chrome.tabs results to name the right window.
void StampWindowId(content::WebContents* contents, SessionID window_id) {
  auto* session = sessions::SessionTabHelper::FromWebContents(contents);
  if (session && session->window_id() != window_id) {
    session->SetWindowID(window_id);
  }
}

class StoneBaseWindow final : public ui::BaseWindow {
 public:
  StoneBaseWindow(Profile* profile, int window_id)
      : profile_(profile), window_id_(window_id) {}

  bool IsActive() const override {
    STExtensionWindow* entry = Entry();
    return entry.focused && entry.window.isKeyWindow;
  }
  bool IsMaximized() const override { return Native().zoomed; }
  bool IsMinimized() const override { return Native().miniaturized; }
  bool IsFullscreen() const override {
    return (Native().styleMask & NSWindowStyleMaskFullScreen) != 0;
  }
  gfx::NativeWindow GetNativeWindow() const override {
    return gfx::NativeWindow(Native());
  }
  gfx::Rect GetRestoredBounds() const override { return GetBounds(); }
  ui::mojom::WindowShowState GetRestoredState() const override {
    return ui::mojom::WindowShowState::kNormal;
  }
  gfx::Rect GetBounds() const override {
    NSWindow* window = Native();
    return window ? gfx::ScreenRectFromNSRect(window.frame) : gfx::Rect();
  }
  void Show() override { Activate(); }
  // Extensions don't get to hide or close the user's window.
  void Hide() override {}
  bool IsVisible() const override { return Native().visible; }
  void ShowInactive() override { [Native() orderFront:nil]; }
  void Close() override {}
  void Activate() override {
    STExtensionWindow* entry = Entry();
    if (entry.activeTab && !entry.focused) {
      [Delegate() extensionActivateTab:entry.activeTab];
    }
    NSWindow* window = entry.window;
    if (window.miniaturized) {
      [window deminiaturize:nil];
    }
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
  }
  void Deactivate() override {}
  void Maximize() override {
    NSWindow* window = Native();
    if (window && !window.zoomed) {
      [window zoom:nil];
    }
  }
  void Minimize() override { [Native() miniaturize:nil]; }
  void Restore() override {
    NSWindow* window = Native();
    if (window.miniaturized) {
      [window deminiaturize:nil];
    } else if (window.zoomed) {
      [window zoom:nil];
    }
  }
  void SetBounds(const gfx::Rect& bounds) override {
    [Native() setFrame:gfx::ScreenRectToNSRect(bounds) display:YES];
  }
  void FlashFrame(bool flash) override {}
  ui::ZOrderLevel GetZOrderLevel() const override {
    return ui::ZOrderLevel::kNormal;
  }
  void SetZOrderLevel(ui::ZOrderLevel order) override {}

 private:
  STExtensionWindow* Entry() const { return FindWindow(profile_, window_id_); }
  NSWindow* Native() const { return Entry().window; }

  raw_ptr<Profile> profile_;
  int window_id_;
};

class StoneWindowController final : public extensions::WindowController {
 public:
  StoneWindowController(std::unique_ptr<StoneBaseWindow> base_window,
                        Profile* profile,
                        int window_id)
      : WindowController(base_window.get(), profile),
        base_window_(std::move(base_window)),
        window_id_(window_id) {
    extensions::WindowControllerList::GetInstance()->AddExtensionWindow(this);
  }

  ~StoneWindowController() override {
    extensions::WindowControllerList::GetInstance()->RemoveExtensionWindow(
        this);
  }

  int GetWindowId() const override { return window_id_; }

  std::string GetWindowTypeText() const override {
    return extensions::api::tabs::ToString(
        extensions::api::tabs::WindowType::kNormal);
  }

  void SetFullscreenMode(bool is_fullscreen,
                         const GURL& extension_url) const override {}

  content::WebContents* GetActiveTab() const override {
    return Entry().activeTab.webContents;
  }

  int GetTabCount() const override { return Tabs().size(); }

  content::WebContents* GetWebContentsAt(int i) const override {
    std::vector<content::WebContents*> tabs = Tabs();
    return i >= 0 && i < static_cast<int>(tabs.size()) ? tabs[i] : nullptr;
  }

  bool IsVisibleToTabsAPIForExtension(
      const extensions::Extension* extension,
      bool include_dev_tools_windows) const override {
    return true;
  }

  base::DictValue CreateWindowValueForExtension(
      const extensions::Extension* extension,
      PopulateTabBehavior populate_tab_behavior,
      extensions::mojom::ContextType context) const override {
    base::DictValue dict;
    dict.Set(extension_misc::kId, window_id_);
    dict.Set("type", GetWindowTypeText());
    dict.Set("focused", window()->IsActive());
    dict.Set("incognito", profile()->IsOffTheRecord());
    dict.Set("alwaysOnTop", false);
    std::string_view state = "normal";
    if (window()->IsMinimized()) {
      state = "minimized";
    } else if (window()->IsFullscreen()) {
      state = "fullscreen";
    } else if (window()->IsMaximized()) {
      state = "maximized";
    }
    dict.Set("state", state);
    const gfx::Rect bounds = window()->GetBounds();
    dict.Set("left", bounds.x());
    dict.Set("top", bounds.y());
    dict.Set("width", bounds.width());
    dict.Set("height", bounds.height());
    if (populate_tab_behavior == kPopulateTabs) {
      dict.Set(extensions::ExtensionTabUtil::kTabsKey,
               CreateTabList(extension, context));
    }
    return dict;
  }

  base::ListValue CreateTabList(
      const extensions::Extension* extension,
      extensions::mojom::ContextType context) const override {
    base::ListValue list;
    std::vector<content::WebContents*> tabs = Tabs();
    for (size_t i = 0; i < tabs.size(); ++i) {
      list.Append(extensions::ExtensionTabUtil::CreateTabObject(
                      tabs[i],
                      extensions::ExtensionTabUtil::GetScrubTabBehavior(
                          extension, context, tabs[i]),
                      extension, nullptr, static_cast<int>(i))
                      .ToValue());
    }
    return list;
  }

  bool OpenOptionsPage(const extensions::Extension* extension,
                       const GURL& url,
                       bool open_in_tab) override {
    id<STExtensionTabsDelegate> delegate = Delegate();
    STProfile* st_profile = ProfileFor(profile());
    id key = [WindowKeys() objectForKey:@(window_id_)];
    if (!delegate || !st_profile || !key) {
      return false;
    }
    return [delegate extensionOpenTabWithURL:net::NSURLWithGURL(url)
                                    inWindow:key
                                     profile:st_profile
                                      active:YES
                                      pinned:NO] != nil;
  }

 private:
  STExtensionWindow* Entry() const { return FindWindow(profile(), window_id_); }

  std::vector<content::WebContents*> Tabs() const {
    std::vector<content::WebContents*> result;
    SessionID id = SessionID::FromSerializedValue(window_id_);
    for (STTab* tab in Entry().tabs) {
      content::WebContents* contents = tab.webContents;
      if (contents && contents->GetBrowserContext() == profile()) {
        StampWindowId(contents, id);
        result.push_back(contents);
      }
    }
    return result;
  }

  std::unique_ptr<StoneBaseWindow> base_window_;
  int window_id_;
};

std::map<int, std::unique_ptr<StoneWindowController>>& Controllers() {
  static base::NoDestructor<
      std::map<int, std::unique_ptr<StoneWindowController>>>
      controllers;
  return *controllers;
}

void SyncWindowControllers() {
  std::set<int> live;
  for (STProfile* st_profile in STApplication.sharedApplication
           .loadedProfiles) {
    Profile* profile = st_profile.nativeProfile;
    for (STExtensionWindow* window in WindowsFor(profile)) {
      int id = WindowIdFor(window.key).id();
      live.insert(id);
      auto& slot = Controllers()[id];
      if (!slot) {
        slot = std::make_unique<StoneWindowController>(
            std::make_unique<StoneBaseWindow>(profile, id), profile, id);
      }
    }
  }
  std::erase_if(Controllers(),
                [&](const auto& entry) { return !live.contains(entry.first); });
}

extensions::TabsEventRouter* RouterFor(content::WebContents* contents) {
  if (g_tab_events_suspended || !contents) {
    return nullptr;
  }
  auto* api = extensions::TabsWindowsAPI::Get(contents->GetBrowserContext());
  return api ? api->tabs_event_router() : nullptr;
}

class ExtensionTabsBridge
    : public extensions::ExtensionTabUtil::ExternalTabsDelegate {
 public:
  std::vector<Tab> GetTabs(content::BrowserContext* context) override {
    std::vector<Tab> result;
    for (STExtensionWindow* window in
         WindowsFor(Profile::FromBrowserContext(context))) {
      SessionID window_id = WindowIdFor(window.key);
      int index = 0;
      for (STTab* tab in window.tabs) {
        content::WebContents* contents = tab.webContents;
        if (!contents || contents->GetBrowserContext() != context) {
          continue;
        }
        StampWindowId(contents, window_id);
        Tab entry;
        entry.contents = contents;
        entry.window_id = window_id.id();
        entry.index = index++;
        entry.active = tab == window.activeTab;
        entry.pinned = [window.pinnedTabs containsObject:tab];
        entry.focused_window = window.focused;
        result.push_back(entry);
      }
    }
    return result;
  }

  content::WebContents* CreateTab(content::BrowserContext* context,
                                  int window_id,
                                  const GURL& url,
                                  bool active,
                                  bool pinned) override {
    id<STExtensionTabsDelegate> delegate = Delegate();
    STProfile* profile = ProfileFor(Profile::FromBrowserContext(context));
    if (!delegate || !profile) {
      return nullptr;
    }
    id key = nil;
    if (window_id >= 0) {
      key = [WindowKeys() objectForKey:@(window_id)];
      if (!key) {
        return nullptr;
      }
    }
    NSURL* page = nil;
    if (!url.SchemeIs("chrome") || url.host() != "newtab") {
      page = net::NSURLWithGURL(url);
    }
    STTab* tab = [delegate extensionOpenTabWithURL:page
                                          inWindow:key
                                           profile:profile
                                            active:active
                                            pinned:pinned];
    return tab.webContents;
  }

  void ActivateTab(content::WebContents* contents) override {
    if (STTab* tab = TabForContents(contents)) {
      [Delegate() extensionActivateTab:tab];
    }
  }
};

}  // namespace

void RegisterTabsWithExtensions() {
  static base::NoDestructor<ExtensionTabsBridge> bridge;
  extensions::ExtensionTabUtil::SetExternalTabsDelegate(bridge.get());
}

// The app adds the tab to a space after creating it, so look it up once the
// current task is done.
void AnnounceTabToExtensions(STTab* tab) {
  __weak STTab* weak_tab = tab;
  dispatch_async(dispatch_get_main_queue(), ^{
    content::WebContents* contents = weak_tab.webContents;
    extensions::TabsEventRouter* router = RouterFor(contents);
    if (!router) {
      return;
    }
    SyncWindowControllers();
    if (auto entry = extensions::ExtensionTabUtil::GetExternalTab(contents)) {
      router->OnExternalTabAdded(*contents, entry->index, entry->active);
    }
  });
}

void RemoveTabFromExtensions(content::WebContents* contents) {
  if (extensions::TabsEventRouter* router = RouterFor(contents)) {
    router->OnExternalTabRemoved(*contents);
  }
}

void SuspendExtensionTabEvents() {
  g_tab_events_suspended = true;
  Controllers().clear();
}

}  // namespace stone_core

@implementation STApplication (ExtensionTabs)

- (void)extensionWindowsDidChange {
  if (!stone_core::g_tab_events_suspended) {
    stone_core::SyncWindowControllers();
  }
}

// Queued behind AnnounceTabToExtensions, so a tab opened in the foreground
// reports onCreated before onActivated.
- (void)extensionTabDidActivate:(STTab*)tab {
  __weak STTab* weak_tab = tab;
  dispatch_async(dispatch_get_main_queue(), ^{
    content::WebContents* contents = weak_tab.webContents;
    if (extensions::TabsEventRouter* router =
            stone_core::RouterFor(contents)) {
      router->OnExternalTabActivated(*contents);
    }
  });
}

@end

@implementation STExtensionWindow

@synthesize key = _key;
@synthesize tabs = _tabs;
@synthesize activeTab = _activeTab;
@synthesize pinnedTabs = _pinnedTabs;
@synthesize focused = _focused;
@synthesize window = _window;

- (instancetype)initWithKey:(id)key
                       tabs:(NSArray<STTab*>*)tabs
                  activeTab:(STTab*)activeTab
                 pinnedTabs:(NSArray<STTab*>*)pinnedTabs
                    focused:(BOOL)focused
                     window:(NSWindow*)window {
  self = [super init];
  if (self) {
    _key = key;
    _tabs = [tabs copy];
    _activeTab = activeTab;
    _pinnedTabs = [pinnedTabs copy];
    _focused = focused;
    _window = window;
  }
  return self;
}

@end
