// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#import "argon_core/browser/ac_internal.h"

#include <algorithm>
#include <cmath>
#include <memory>

#include "base/strings/sys_string_conversions.h"
#include "base/functional/bind.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "chrome/browser/extensions/extension_tab_util.h"
#include "components/sessions/content/session_tab_helper.h"
#include "chrome/browser/printing/print_view_manager_common.h"
#include "chrome/browser/profiles/profile.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/find_in_page/find_types.h"
#include "components/zoom/page_zoom.h"
#include "content/public/browser/host_zoom_map.h"
#include "content/public/browser/reload_type.h"
#include "components/viz/common/frame_sinks/copy_output_result.h"
#include "content/public/browser/render_widget_host_view.h"
#include "skia/ext/skia_utils_mac.h"
#include "third_party/blink/public/common/page/page_zoom.h"
#include "content/public/common/page_zoom.h"
#include "content/public/browser/media_session.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/web_contents.h"
#include "argon_core/browser/ac_tab_host.h"
#include "net/base/apple/url_conversions.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/native_ui_types.h"
#include "url/gurl.h"

namespace {

ACTabOpenDisposition ToDisposition(WindowOpenDisposition disposition) {
  switch (disposition) {
    case WindowOpenDisposition::NEW_BACKGROUND_TAB:
      return ACTabOpenDispositionBackground;
    case WindowOpenDisposition::NEW_POPUP:
      return ACTabOpenDispositionPopup;
    case WindowOpenDisposition::NEW_WINDOW:
      return ACTabOpenDispositionWindow;
    default:
      return ACTabOpenDispositionForeground;
  }
}

NSHashTable<ACTab*>* LiveTabs() {
  static NSHashTable<ACTab*>* tabs = [NSHashTable weakObjectsHashTable];
  return tabs;
}

}  // namespace

namespace argon_core {

void RegisterTabsWithExtensions() {
  extensions::ExtensionTabUtil::SetExternalTabLookup(base::BindRepeating(
      [](int tab_id,
         content::BrowserContext* context) -> content::WebContents* {
        for (ACTab* tab in LiveTabs().allObjects) {
          content::WebContents* contents = tab.webContents;
          if (contents && contents->GetBrowserContext() == context &&
              sessions::SessionTabHelper::IdForTab(contents).id() == tab_id) {
            return contents;
          }
        }
        return nullptr;
      }));
}

void CloseAllTabs() {
  for (ACTab* tab in LiveTabs().allObjects) {
    [tab close];
  }
}

}  // namespace argon_core

@implementation ACTab {
  ACProfile* _profile;
  std::unique_ptr<argon_core::ACTabHost> _host;
}

@synthesize delegate = _delegate;

- (instancetype)initWithProfile:(ACProfile*)profile
                    webContents:(std::unique_ptr<content::WebContents>)contents {
  self = [super init];
  if (self) {
    _profile = profile;
    _host =
        std::make_unique<argon_core::ACTabHost>(self, std::move(contents));
    [LiveTabs() addObject:self];
  }
  return self;
}

- (void)dealloc {
  _host.reset();
}

- (content::WebContents*)webContents {
  return _host ? _host->contents() : nullptr;
}

- (ACProfile*)profile {
  return _profile;
}

- (NSView*)view {
  return _host->view();
}

- (NSURL*)url {
  const GURL& url = self.webContents->GetVisibleURL();
  return url.is_valid() ? net::NSURLWithGURL(url) : nil;
}

- (NSString*)title {
  return base::SysUTF16ToNSString(self.webContents->GetTitle());
}

- (BOOL)isLoading {
  return self.webContents->IsLoading();
}

- (double)loadProgress {
  return self.webContents->GetLoadProgress();
}

- (BOOL)canGoBack {
  return self.webContents->GetController().CanGoBack();
}

- (BOOL)canGoForward {
  return self.webContents->GetController().CanGoForward();
}

- (NSImage*)favicon {
  auto* driver = favicon::ContentFaviconDriver::FromWebContents(self.webContents);
  if (!driver || !driver->FaviconIsValid()) {
    return nil;
  }
  gfx::Image image = driver->GetFavicon();
  return image.IsEmpty() ? nil : image.ToNSImage();
}

- (BOOL)isVisible {
  return self.webContents->GetVisibility() == content::Visibility::VISIBLE;
}

- (void)setVisible:(BOOL)visible {
  _host->SetVisible(visible);
}

- (void)toggleDevTools {
  _host->ToggleDevTools();
}

- (void)showDevToolsConsole {
  _host->ShowDevTools(argon_core::ACTabHost::DevToolsPanel::kConsole);
}

- (void)inspectElement {
  _host->ShowDevTools(argon_core::ACTabHost::DevToolsPanel::kInspect);
}

- (void)reloadBypassingCache {
  self.webContents->GetController().Reload(content::ReloadType::BYPASSING_CACHE,
                                           /*check_for_repost=*/true);
}

- (void)zoomIn {
  zoom::PageZoom::Zoom(self.webContents, content::PAGE_ZOOM_IN);
}

- (void)zoomOut {
  zoom::PageZoom::Zoom(self.webContents, content::PAGE_ZOOM_OUT);
}

- (void)resetZoom {
  zoom::PageZoom::Zoom(self.webContents, content::PAGE_ZOOM_RESET);
}

- (BOOL)hasMedia {
  return _host->media().active;
}

- (BOOL)isPlayingMedia {
  return _host->media().playing;
}

- (BOOL)isAudible {
  return self.webContents->IsCurrentlyAudible();
}

- (BOOL)isMuted {
  return self.webContents->IsAudioMuted();
}

- (void)setMuted:(BOOL)muted {
  self.webContents->SetAudioMuted(muted);
  [self hostMediaChanged];
}

- (NSString*)mediaTitle {
  return base::SysUTF16ToNSString(_host->media().title);
}

- (BOOL)canPlayPreviousTrack {
  return _host->media().can_previous;
}

- (BOOL)canPlayNextTrack {
  return _host->media().can_next;
}

- (BOOL)canEnterPictureInPicture {
  return _host->media().can_picture_in_picture;
}

- (BOOL)isInPictureInPicture {
  return _host->media().in_picture_in_picture;
}

- (void)playMedia {
  content::MediaSession::Get(self.webContents)
      ->Resume(content::MediaSession::SuspendType::kUI);
}

- (void)pauseMedia {
  content::MediaSession::Get(self.webContents)
      ->Suspend(content::MediaSession::SuspendType::kUI);
}

- (void)previousTrack {
  content::MediaSession::Get(self.webContents)->PreviousTrack();
}

- (void)nextTrack {
  content::MediaSession::Get(self.webContents)->NextTrack();
}

- (HostContentSettingsMap*)contentSettingsForURL:(GURL*)url {
  content::WebContents* contents = self.webContents;
  if (!contents) {
    return nullptr;
  }
  *url = contents->GetLastCommittedURL();
  if (!url->SchemeIsHTTPOrHTTPS()) {
    return nullptr;
  }
  return HostContentSettingsMapFactory::GetForProfile(
      Profile::FromBrowserContext(contents->GetBrowserContext()));
}

- (BOOL)autoPictureInPictureAllowed {
  GURL url;
  HostContentSettingsMap* map = [self contentSettingsForURL:&url];
  if (!map) {
    return NO;
  }
  return map->GetContentSetting(url, url,
                                ContentSettingsType::AUTO_PICTURE_IN_PICTURE) !=
         CONTENT_SETTING_BLOCK;
}

- (void)setAutoPictureInPictureAllowed:(BOOL)allowed {
  GURL url;
  HostContentSettingsMap* map = [self contentSettingsForURL:&url];
  if (!map) {
    return;
  }
  map->SetContentSettingDefaultScope(
      url, url, ContentSettingsType::AUTO_PICTURE_IN_PICTURE,
      allowed ? CONTENT_SETTING_ALLOW : CONTENT_SETTING_BLOCK);
}

- (void)togglePictureInPicture {
  auto* session = content::MediaSession::Get(self.webContents);
  if (_host->media().in_picture_in_picture) {
    session->ExitPictureInPicture();
  } else {
    session->EnterPictureInPicture();
  }
}

- (void)stopMedia {
  content::MediaSession::Get(self.webContents)
      ->Stop(content::MediaSession::SuspendType::kUI);
}

- (NSInteger)zoomPercent {
  double level = content::HostZoomMap::GetZoomLevel(self.webContents);
  return std::lround(blink::ZoomLevelToZoomFactor(level) * 100);
}

- (void)captureVisibleContentWithCompletion:(void (^)(NSImage*))completion {
  void (^callback)(NSImage*) = [completion copy];
  content::RenderWidgetHostView* view =
      self.webContents->GetRenderWidgetHostView();
  if (!view || !view->IsSurfaceAvailableForCopy()) {
    callback(nil);
    return;
  }
  // The copy can finish on another sequence, so the result hops back to main.
  view->CopyFromSurface(
      gfx::Rect(), gfx::Size(), base::Seconds(5),
      base::BindOnce(
          [](void (^callback)(NSImage*),
             const content::CopyFromSurfaceResult& result) {
            NSImage* image = nil;
            if (result.has_value() && !result->bitmap.drawsNothing()) {
              image = skia::SkBitmapToNSImage(result->bitmap);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
              callback(image);
            });
          },
          callback));
}

- (void)print {
  printing::StartPrint(self.webContents, /*print_preview_disabled=*/false,
                       /*has_selection=*/false);
}

- (void)printUsingSystemDialog {
  printing::StartBasicPrint(self.webContents);
}

- (void)savePage {
  self.webContents->OnSavePage();
}

- (void)findText:(NSString*)text
         forward:(BOOL)forward
   caseSensitive:(BOOL)caseSensitive {
  auto* helper = find_in_page::FindTabHelper::FromWebContents(self.webContents);
  if (!helper) {
    return;
  }
  if (text.length == 0) {
    helper->StopFinding(find_in_page::SelectionAction::kClear);
    return;
  }
  helper->StartFinding(base::SysNSStringToUTF16(text), forward, caseSensitive,
                       /*find_match=*/true);
}

- (void)stopFindingClearingSelection:(BOOL)clearSelection {
  auto* helper = find_in_page::FindTabHelper::FromWebContents(self.webContents);
  if (helper) {
    helper->StopFinding(clearSelection
                            ? find_in_page::SelectionAction::kClear
                            : find_in_page::SelectionAction::kKeep);
  }
}

- (NSString*)findText {
  auto* helper = find_in_page::FindTabHelper::FromWebContents(self.webContents);
  if (!helper) {
    return @"";
  }
  std::u16string text = helper->find_text().empty()
                            ? helper->previous_find_text()
                            : helper->find_text();
  return base::SysUTF16ToNSString(text);
}

- (void)loadURL:(NSURL*)url {
  content::NavigationController::LoadURLParams params(net::GURLWithNSURL(url));
  params.transition_type = ui::PageTransitionFromInt(
      ui::PAGE_TRANSITION_TYPED | ui::PAGE_TRANSITION_FROM_ADDRESS_BAR);
  self.webContents->GetController().LoadURLWithParams(params);
}

- (void)goBack {
  if (self.canGoBack) {
    self.webContents->GetController().GoBack();
  }
}

- (void)goForward {
  if (self.canGoForward) {
    self.webContents->GetController().GoForward();
  }
}

- (void)reload {
  self.webContents->GetController().Reload(content::ReloadType::NORMAL, true);
}

- (void)stop {
  self.webContents->Stop();
}

- (void)focus {
  self.webContents->Focus();
}

- (void)close {
  _host.reset();
}

#pragma mark - Host callbacks

- (void)hostDidChange:(content::InvalidateTypes)flags {
  id<ACTabDelegate> delegate = self.delegate;
  if ((flags & content::INVALIDATE_TYPE_URL) &&
      [delegate respondsToSelector:@selector(tabDidChangeURL:)]) {
    [delegate tabDidChangeURL:self];
  }
  if ((flags & content::INVALIDATE_TYPE_TITLE) &&
      [delegate respondsToSelector:@selector(tabDidChangeTitle:)]) {
    [delegate tabDidChangeTitle:self];
  }
  if ([delegate respondsToSelector:@selector(tabDidChangeNavigationState:)]) {
    [delegate tabDidChangeNavigationState:self];
  }
}

- (void)hostMediaChanged {
  id<ACTabDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(tabDidChangeMedia:)]) {
    [delegate tabDidChangeMedia:self];
  }
}

- (void)hostLoadingChanged {
  id<ACTabDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(tabDidChangeLoading:)]) {
    [delegate tabDidChangeLoading:self];
  }
}

- (void)hostFindMatches:(int)matches active:(int)active {
  id<ACTabDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(tab:
                                       didUpdateFindMatches:activeMatch:)]) {
    [delegate tab:self
        didUpdateFindMatches:std::max(matches, 0)
                 activeMatch:std::max(active, 0)];
  }
}

- (void)hostFaviconChanged {
  id<ACTabDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(tabDidChangeFavicon:)]) {
    [delegate tabDidChangeFavicon:self];
  }
}

- (void)hostRequestedClose {
  id<ACTabDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(tabDidRequestClose:)]) {
    [delegate tabDidRequestClose:self];
  }
}

- (void)hostRequestedFullscreen:(BOOL)fullscreen {
  id<ACTabDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(tab:didRequestFullscreen:)]) {
    [delegate tab:self didRequestFullscreen:fullscreen];
  }
}

- (void)hostOpenedContents:(std::unique_ptr<content::WebContents>)contents
               disposition:(WindowOpenDisposition)disposition {
  ACTab* newTab = [[ACTab alloc] initWithProfile:_profile
                                     webContents:std::move(contents)];
  id<ACTabDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(tab:didRequestNewTab:disposition:)]) {
    [delegate tab:self
        didRequestNewTab:newTab
             disposition:ToDisposition(disposition)];
  }
  // Chromium uses the returned WebContents after this call; keep an unclaimed
  // tab alive until the current task finishes.
  dispatch_async(dispatch_get_main_queue(), ^{
    (void)newTab;
  });
}

@end
