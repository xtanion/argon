// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#import "argon_core/browser/ac_tab_host.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <cmath>
#include <set>

#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "chrome/browser/devtools/chrome_devtools_manager_delegate.h"
#include "chrome/browser/devtools/devtools_toggle_action.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/favicon/favicon_utils.h"
#include "chrome/browser/file_select_helper.h"
#include "chrome/browser/printing/printing_init.h"
#include "chrome/browser/ui/find_bar/find_bar_state.h"
#include "components/find_in_page/find_tab_helper.h"
#include "chrome/browser/ui/views/eye_dropper/eye_dropper.h"
#include "components/javascript_dialogs/app_modal_dialog_manager.h"
#include "content/public/browser/eye_dropper.h"
#include "content/public/browser/file_select_listener.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "chrome/browser/media/webrtc/media_capture_devices_dispatcher.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_window_manager.h"
#include "chrome/browser/extensions/api/web_navigation/web_navigation_tab_observer.h"
#include "chrome/browser/extensions/navigation_extension_enabler.h"
#include "chrome/browser/extensions/tab_helper.h"
#include "chrome/browser/ui/tab_helpers.h"
#include "extensions/browser/view_type_utils.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/permissions/permission_request_manager.h"
#include "components/web_modal/web_contents_modal_dialog_manager.h"
#include "content/public/browser/media_session.h"
#include "content/public/browser/navigation_controller.h"
#include "services/media_session/public/cpp/media_metadata.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#import "argon_core/browser/ac_internal.h"
#import "argon_core/browser/ac_permission_prompt.h"
#include "third_party/blink/public/mojom/frame/fullscreen.mojom.h"
#include "ui/base/window_open_disposition.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "ui/views/widget/widget.h"

@interface ACTabContainerView : NSView
@property(copy) void (^onLayout)(void);
@end

@implementation ACTabContainerView

@synthesize onLayout = _onLayout;

- (BOOL)isFlipped {
  return YES;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
  if (_onLayout) {
    _onLayout();
  }
}

@end

@interface ACTab (Host)
- (void)hostDidChange:(content::InvalidateTypes)flags;
- (void)hostLoadingChanged;
- (void)hostMediaChanged;
- (void)hostFaviconChanged;
- (void)hostFindMatches:(int)matches active:(int)active;
- (void)hostRequestedClose;
- (void)hostRequestedFullscreen:(BOOL)fullscreen;
- (void)hostOpenedContents:(std::unique_ptr<content::WebContents>)contents
               disposition:(WindowOpenDisposition)disposition;
@end

namespace argon_core {

namespace {

std::set<ACTabHost*>& Hosts() {
  static base::NoDestructor<std::set<ACTabHost*>> hosts;
  return *hosts;
}

NSRect ToNSRect(const gfx::Rect& rect) {
  return NSMakeRect(rect.x(), rect.y(), rect.width(), rect.height());
}

}  // namespace

ACTabHost::ACTabHost(ACTab* owner,
                     std::unique_ptr<content::WebContents> contents)
    : content::WebContentsObserver(contents.get()),
      owner_(owner),
      contents_(std::move(contents)) {
  contents_->SetDelegate(this);
  ChromeDevToolsManagerDelegate::MarkAsEmbedderTab(contents_.get());
  TabHelpers::AttachTabHelpers(contents_.get(), /*enable_browser_autofill=*/true);
  favicon::CreateContentFaviconDriverForWebContents(contents_.get());
  // Chrome attaches these in TabFeatures, which only runs for Browser tabs.
  FindBarState::ConfigureWebContents(contents_.get());
  find_in_page::FindTabHelper::FromWebContents(contents_.get())
      ->AddObserver(this);
  printing::InitializePrintingForWebContents(contents_.get());
  if (extensions::GetViewType(contents_.get()) ==
      extensions::mojom::ViewType::kInvalid) {
    extensions::SetViewType(contents_.get(),
                            extensions::mojom::ViewType::kTabContents);
  }
  extensions::WebNavigationTabObserver::CreateForWebContents(contents_.get());
  extensions::TabHelper::CreateForWebContents(contents_.get());
  navigation_extension_enabler_ =
      std::make_unique<extensions::NavigationExtensionEnabler>(contents_.get());
  favicon::ContentFaviconDriver::FromWebContents(contents_.get())
      ->AddObserver(this);

  if (auto* permissions =
          permissions::PermissionRequestManager::FromWebContents(
              contents_.get())) {
    permissions->set_view_factory_for_testing(
        base::BindRepeating(&ACPermissionPrompt::Create));
  }

  web_modal::WebContentsModalDialogManager::CreateForWebContents(
      contents_.get());
  web_modal::WebContentsModalDialogManager::FromWebContents(contents_.get())
      ->SetDelegate(this);

  NSView* view = contents_->GetNativeView().GetNativeNSView();
  ACTabContainerView* container = [[ACTabContainerView alloc] init];
  [container addSubview:view];
  container_ = container;
  ACTabHost* self_host = this;
  container.onLayout = ^{
    self_host->LayoutContents();
  };
  if (Hosts().empty()) {
    DevToolsWindow::SetEmbedderDockCallback(
        base::BindRepeating(&ACTabHost::OnDevToolsChanged));
  }
  Hosts().insert(this);
  content::MediaSession::Get(contents_.get())
      ->AddObserver(media_receiver_.BindNewPipeAndPassRemote());

  view.postsFrameChangedNotifications = YES;
  ACTabHost* host = this;
  frame_observer_ = [NSNotificationCenter.defaultCenter
      addObserverForName:NSViewFrameDidChangeNotification
                  object:view
                   queue:nil
              usingBlock:^(NSNotification*) {
                host->NotifyPositionRequiresUpdate();
              }];
}

ACTabHost::~ACTabHost() {
  DetachDevToolsDialogs();
  Hosts().erase(this);
  static_cast<ACTabContainerView*>(container_).onLayout = nil;
  [NSNotificationCenter.defaultCenter removeObserver:frame_observer_];
  web_modal::WebContentsModalDialogManager::FromWebContents(contents_.get())
      ->SetDelegate(nullptr);
  for (web_modal::ModalDialogHostObserver& observer : modal_observers_) {
    observer.OnHostDestroying();
  }
  favicon::ContentFaviconDriver::FromWebContents(contents_.get())
      ->RemoveObserver(this);
  if (auto* find = find_in_page::FindTabHelper::FromWebContents(
          contents_.get())) {
    find->RemoveObserver(this);
  }
  Observe(nullptr);
  contents_->SetDelegate(nullptr);
}

content::WebContents* ACTabHost::OpenURLFromTab(
    content::WebContents* source,
    const content::OpenURLParams& params,
    base::OnceCallback<void(content::NavigationHandle&)>
        navigation_handle_callback) {
  if (params.disposition == WindowOpenDisposition::CURRENT_TAB) {
    base::WeakPtr<content::NavigationHandle> handle =
        source->GetController().LoadURLWithParams(
            content::NavigationController::LoadURLParams(params));
    if (handle && navigation_handle_callback) {
      std::move(navigation_handle_callback).Run(*handle);
    }
    return source;
  }

  content::WebContents::CreateParams create_params(
      source->GetBrowserContext());
  create_params.initially_hidden =
      params.disposition == WindowOpenDisposition::NEW_BACKGROUND_TAB;
  std::unique_ptr<content::WebContents> new_contents =
      content::WebContents::Create(create_params);
  content::WebContents* raw = new_contents.get();
  base::WeakPtr<content::NavigationHandle> handle =
      raw->GetController().LoadURLWithParams(
          content::NavigationController::LoadURLParams(params));
  if (handle && navigation_handle_callback) {
    std::move(navigation_handle_callback).Run(*handle);
  }
  [owner_ hostOpenedContents:std::move(new_contents)
                 disposition:params.disposition];
  return raw;
}

content::WebContents* ACTabHost::AddNewContents(
    content::WebContents* source,
    std::unique_ptr<content::WebContents> new_contents,
    const GURL& target_url,
    WindowOpenDisposition disposition,
    const blink::mojom::WindowFeatures& window_features,
    bool user_gesture,
    bool* was_blocked) {
  content::WebContents* raw = new_contents.get();
  [owner_ hostOpenedContents:std::move(new_contents) disposition:disposition];
  return raw;
}

void ACTabHost::CloseContents(content::WebContents* source) {
  [owner_ hostRequestedClose];
}

void ACTabHost::NavigationStateChanged(content::WebContents* source,
                                       content::InvalidateTypes changed_flags) {
  [owner_ hostDidChange:changed_flags];
  if (changed_flags & content::INVALIDATE_TYPE_AUDIO) {
    [owner_ hostMediaChanged];
  }
}

void ACTabHost::MediaSessionInfoChanged(
    media_session::mojom::MediaSessionInfoPtr info) {
  using State = media_session::mojom::MediaSessionInfo::SessionState;
  media_.active = info && info->is_controllable &&
                  info->state != State::kInactive;
  media_.playing =
      media_.active && info->playback_state ==
                           media_session::mojom::MediaPlaybackState::kPlaying;
  media_.in_picture_in_picture =
      info && info->picture_in_picture_state ==
                  media_session::mojom::MediaPictureInPictureState::
                      kInPictureInPicture;
  [owner_ hostMediaChanged];
}

void ACTabHost::MediaSessionMetadataChanged(
    const std::optional<media_session::MediaMetadata>& metadata) {
  media_.title = metadata ? metadata->title : std::u16string();
  [owner_ hostMediaChanged];
}

void ACTabHost::MediaSessionActionsChanged(
    const std::vector<media_session::mojom::MediaSessionAction>& actions) {
  using Action = media_session::mojom::MediaSessionAction;
  auto has = [&](Action action) {
    return std::find(actions.begin(), actions.end(), action) != actions.end();
  };
  media_.can_previous = has(Action::kPreviousTrack);
  media_.can_next = has(Action::kNextTrack);
  media_.can_picture_in_picture = has(Action::kEnterPictureInPicture);
  [owner_ hostMediaChanged];
}

void ACTabHost::MediaSessionImagesChanged(
    const base::flat_map<media_session::mojom::MediaSessionImageType,
                         std::vector<media_session::MediaImage>>& images) {}

void ACTabHost::MediaSessionPositionChanged(
    const std::optional<media_session::MediaPosition>& position) {}

void ACTabHost::LoadingStateChanged(content::WebContents* source,
                                    bool should_show_loading_ui) {
  [owner_ hostLoadingChanged];
}

void ACTabHost::EnterFullscreenModeForTab(
    content::RenderFrameHost* requesting_frame,
    const blink::mojom::FullscreenOptions& options) {
  fullscreen_ = true;
  [owner_ hostRequestedFullscreen:YES];
}

void ACTabHost::ExitFullscreenModeForTab(content::WebContents* source) {
  fullscreen_ = false;
  [owner_ hostRequestedFullscreen:NO];
}

bool ACTabHost::IsFullscreenForTabOrPending(
    const content::WebContents* source) {
  return fullscreen_;
}

void ACTabHost::RequestMediaAccessPermission(
    content::WebContents* web_contents,
    const content::MediaStreamRequest& request,
    content::MediaResponseCallback callback) {
  MediaCaptureDevicesDispatcher::GetInstance()->ProcessMediaAccessRequest(
      web_contents, request, std::move(callback), /*extension=*/nullptr);
}

bool ACTabHost::CheckMediaAccessPermission(
    content::RenderFrameHost* render_frame_host,
    const url::Origin& security_origin,
    blink::mojom::MediaStreamType type) {
  return MediaCaptureDevicesDispatcher::GetInstance()
      ->CheckMediaAccessPermission(render_frame_host, security_origin, type);
}

// Tab-modal JS dialogs require a foremost Chrome Browser, which the native
// shell never has; app-modal ones only need the page's window.
content::JavaScriptDialogManager* ACTabHost::GetJavaScriptDialogManager(
    content::WebContents* source) {
  return javascript_dialogs::AppModalDialogManager::GetInstance();
}

void ACTabHost::RunFileChooser(
    content::RenderFrameHost* render_frame_host,
    scoped_refptr<content::FileSelectListener> listener,
    const blink::mojom::FileChooserParams& params) {
  FileSelectHelper::RunFileChooser(render_frame_host, std::move(listener),
                                   params);
}

void ACTabHost::EnumerateDirectory(
    content::WebContents* web_contents,
    scoped_refptr<content::FileSelectListener> listener,
    const base::FilePath& path) {
  FileSelectHelper::EnumerateDirectory(web_contents, std::move(listener), path);
}

std::unique_ptr<content::EyeDropper> ACTabHost::OpenEyeDropper(
    content::RenderFrameHost* frame,
    content::EyeDropperListener* listener) {
  return ShowEyeDropper(frame, listener);
}

content::PictureInPictureResult ACTabHost::EnterPictureInPicture(
    content::WebContents* web_contents) {
  return PictureInPictureWindowManager::GetInstance()
      ->EnterVideoPictureInPicture(web_contents);
}

void ACTabHost::ExitPictureInPicture() {
  PictureInPictureWindowManager::GetInstance()->ExitPictureInPicture();
}

void ACTabHost::LoadProgressChanged(double progress) {
  [owner_ hostLoadingChanged];
}

void ACTabHost::OnFaviconUpdated(favicon::FaviconDriver* favicon_driver,
                                 NotificationIconType notification_icon_type,
                                 const GURL& icon_url,
                                 bool icon_url_changed,
                                 const gfx::Image& image) {
  if (notification_icon_type == NON_TOUCH_16_DIP) {
    [owner_ hostFaviconChanged];
  }
}

// Pages may swallow any shortcut, so the ones Chrome reserves for the browser
// (quit, close, new tab, new window) skip the renderer.
content::KeyboardEventProcessingResult ACTabHost::PreHandleKeyboardEvent(
    content::WebContents* source,
    const input::NativeWebKeyboardEvent& event) {
  NSEvent* ns_event = event.os_event.Get();
  if (ns_event.type != NSEventTypeKeyDown) {
    return content::KeyboardEventProcessingResult::NOT_HANDLED;
  }
  NSEventModifierFlags flags = ns_event.modifierFlags &
                               NSEventModifierFlagDeviceIndependentFlagsMask;
  if (!(flags & NSEventModifierFlagCommand) ||
      (flags & (NSEventModifierFlagControl | NSEventModifierFlagOption))) {
    return content::KeyboardEventProcessingResult::NOT_HANDLED;
  }
  NSString* key = ns_event.charactersIgnoringModifiers.lowercaseString;
  static NSSet<NSString*>* reserved = [NSSet setWithArray:@[ @"q", @"w", @"t", @"n" ]];
  if (![reserved containsObject:key]) {
    return content::KeyboardEventProcessingResult::NOT_HANDLED;
  }
  return [NSApp.mainMenu performKeyEquivalent:ns_event]
             ? content::KeyboardEventProcessingResult::HANDLED
             : content::KeyboardEventProcessingResult::NOT_HANDLED;
}

// Shortcuts the page did not consume go to the app's menu, as in content_shell.
bool ACTabHost::HandleKeyboardEvent(
    content::WebContents* source,
    const input::NativeWebKeyboardEvent& event) {
  if (event.skip_if_unhandled) {
    return false;
  }
  NSEvent* ns_event = event.os_event.Get();
  if (ns_event.type != NSEventTypeKeyDown) {
    return false;
  }
  return [NSApp.mainMenu performKeyEquivalent:ns_event];
}

void ACTabHost::SetWebContentsBlocked(content::WebContents* web_contents,
                                      bool blocked) {
  auto& block = web_contents == contents_.get() ? input_block_
                                                 : devtools_input_block_;
  if (blocked) {
    block.emplace(web_contents->IgnoreInputEvents(std::nullopt));
  } else {
    block.reset();
  }
}

web_modal::WebContentsModalDialogHost*
ACTabHost::GetWebContentsModalDialogHost(content::WebContents* web_contents) {
  return this;
}

bool ACTabHost::IsWebContentsVisible(content::WebContents* web_contents) {
  return web_contents->GetVisibility() == content::Visibility::VISIBLE;
}

gfx::NativeView ACTabHost::GetHostView() const {
  return contents_->GetNativeView();
}

gfx::Point ACTabHost::GetDialogPosition(const gfx::Size& size) {
  gfx::Size host = contents_->GetContainerBounds().size();
  return gfx::Point(std::max(0, (host.width() - size.width()) / 2), 0);
}

gfx::Size ACTabHost::GetMaximumDialogSize() {
  return contents_->GetContainerBounds().size();
}

void ACTabHost::AddObserver(web_modal::ModalDialogHostObserver* observer) {
  modal_observers_.AddObserver(observer);
}

void ACTabHost::RemoveObserver(web_modal::ModalDialogHostObserver* observer) {
  modal_observers_.RemoveObserver(observer);
}

void ACTabHost::NotifyPositionRequiresUpdate() {
  for (web_modal::ModalDialogHostObserver& observer : modal_observers_) {
    observer.OnPositionRequiresUpdate();
  }
}

// The host view is plain AppKit, so constrained_window cannot position the
// dialog: pin it to the top centre of the page and attach it as a child window
// so it follows the browser window.
bool ACTabHost::PlaceDialog(gfx::NativeWindow dialog, const gfx::Size& size) {
  NSView* view = contents_->GetNativeView().GetNativeNSView();
  NSWindow* host_window = view.window;
  NSWindow* window = dialog.GetNativeNSWindow();
  views::Widget* widget = views::Widget::GetWidgetForNativeWindow(dialog);
  if (!host_window || !window || !widget) {
    return false;
  }
  NSRect page = [host_window convertRectToScreen:[view convertRect:view.bounds
                                                             toView:nil]];
  NSRect frame = NSMakeRect(std::round(NSMidX(page) - size.width() / 2.0),
                            NSMaxY(page) - size.height(), size.width(),
                            size.height());
  widget->SetBounds(gfx::ScreenRectFromNSRect(frame));
  if (window.parentWindow != host_window &&
      IsWebContentsVisible(contents_.get())) {
    [window.parentWindow removeChildWindow:window];
    [host_window addChildWindow:window ordered:NSWindowAbove];
  }
  return true;
}

// static
void ACTabHost::OnDevToolsChanged(content::WebContents* inspected) {
  for (ACTabHost* host : Hosts()) {
    if (host->contents() == inspected) {
      host->UpdateDevTools();
      return;
    }
  }
}

void ACTabHost::ShowDevTools(DevToolsPanel panel) {
  DevToolsWindow::ToggleDevToolsWindowForEmbedder(
      contents_.get(), panel == DevToolsPanel::kConsole
                           ? DevToolsToggleAction::ShowConsolePanel()
                           : DevToolsToggleAction::Inspect());
}

void ACTabHost::OnFindResultAvailable(content::WebContents* web_contents) {
  const find_in_page::FindNotificationDetails& result =
      find_in_page::FindTabHelper::FromWebContents(web_contents)->find_result();
  [owner_ hostFindMatches:result.number_of_matches()
                   active:result.active_match_ordinal()];
}

void ACTabHost::ToggleDevTools() {
  DevToolsWindow::ToggleDevToolsWindowForEmbedder(
      contents_.get(), DevToolsToggleAction::Toggle());
}

void ACTabHost::UpdateDevTools() {
  DevToolsContentsResizingStrategy strategy;
  content::WebContents* devtools =
      DevToolsWindow::GetInTabWebContents(contents_.get(), &strategy);
  if (devtools != devtools_) {
    if (devtools_) {
      [devtools_->GetNativeView().GetNativeNSView() removeFromSuperview];
      DetachDevToolsDialogs();
    }
    devtools_ = devtools;
    if (devtools_) {
      // Tab-modal dialogs raised by DevTools itself (e.g. folder access for
      // Workspaces) are hosted over this tab.
      web_modal::WebContentsModalDialogManager::CreateForWebContents(
          devtools_);
      web_modal::WebContentsModalDialogManager::FromWebContents(devtools_)
          ->SetDelegate(this);
      [container_ addSubview:devtools_->GetNativeView().GetNativeNSView()
                  positioned:NSWindowBelow
                  relativeTo:contents_->GetNativeView().GetNativeNSView()];
      if (IsWebContentsVisible(contents_.get())) {
        devtools_->WasShown();
      }
    }
  }
  devtools_strategy_.CopyFrom(strategy);
  LayoutContents();
}

void ACTabHost::DetachDevToolsDialogs() {
  devtools_input_block_.reset();
  if (!devtools_) {
    return;
  }
  auto* manager =
      web_modal::WebContentsModalDialogManager::FromWebContents(devtools_);
  if (manager && manager->delegate() == this) {
    manager->SetDelegate(nullptr);
  }
}

void ACTabHost::LayoutContents() {
  NSView* page = contents_->GetNativeView().GetNativeNSView();
  NSRect bounds = container_.bounds;
  if (!devtools_) {
    page.frame = bounds;
    return;
  }
  gfx::Rect devtools_bounds;
  gfx::Rect page_bounds;
  ApplyDevToolsContentsResizingStrategy(
      devtools_strategy_,
      gfx::Rect(NSWidth(bounds), NSHeight(bounds)), &devtools_bounds,
      &page_bounds);
  devtools_->GetNativeView().GetNativeNSView().frame =
      ToNSRect(devtools_bounds);
  page.frame = ToNSRect(page_bounds);
}

void ACTabHost::SetVisible(bool visible) {
  if (visible) {
    contents_->WasShown();
  } else {
    contents_->WasHidden();
  }
  if (devtools_) {
    if (visible) {
      devtools_->WasShown();
    } else {
      devtools_->WasHidden();
    }
  }
}

}  // namespace argon_core
