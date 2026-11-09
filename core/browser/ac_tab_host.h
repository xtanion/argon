// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef ARGON_CORE_BROWSER_AC_TAB_HOST_H_
#define ARGON_CORE_BROWSER_AC_TAB_HOST_H_

#include <memory>
#include <optional>

#include "base/memory/raw_ptr.h"
#include "base/observer_list.h"
#include "chrome/browser/devtools/devtools_contents_resizing_strategy.h"
#include "components/favicon/core/favicon_driver_observer.h"
#include "components/find_in_page/find_result_observer.h"
#include "components/web_modal/web_contents_modal_dialog_host.h"
#include "components/web_modal/web_contents_modal_dialog_manager_delegate.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_delegate.h"
#include "content/public/browser/web_contents_observer.h"

@class NSObject;
@class NSView;

@class ACTab;

namespace argon_core {

// Owns a tab's WebContents and forwards its events to the Obj-C ACTab.
class ACTabHost : public content::WebContentsDelegate,
                  public content::WebContentsObserver,
                  public favicon::FaviconDriverObserver,
                  public find_in_page::FindResultObserver,
                  public web_modal::WebContentsModalDialogManagerDelegate,
                  public web_modal::WebContentsModalDialogHost {
 public:
  ACTabHost(ACTab* owner, std::unique_ptr<content::WebContents> contents);
  ACTabHost(const ACTabHost&) = delete;
  ACTabHost& operator=(const ACTabHost&) = delete;
  ~ACTabHost() override;

  content::WebContents* contents() { return contents_.get(); }

  // The page plus any docked DevTools.
  NSView* view() const { return container_; }
  void SetVisible(bool visible);
  void ToggleDevTools();
  enum class DevToolsPanel { kConsole, kInspect };
  void ShowDevTools(DevToolsPanel panel);

  // find_in_page::FindResultObserver:
  void OnFindResultAvailable(content::WebContents* web_contents) override;

  // content::WebContentsDelegate:
  content::WebContents* OpenURLFromTab(
      content::WebContents* source,
      const content::OpenURLParams& params,
      base::OnceCallback<void(content::NavigationHandle&)>
          navigation_handle_callback) override;
  content::WebContents* AddNewContents(
      content::WebContents* source,
      std::unique_ptr<content::WebContents> new_contents,
      const GURL& target_url,
      WindowOpenDisposition disposition,
      const blink::mojom::WindowFeatures& window_features,
      bool user_gesture,
      bool* was_blocked) override;
  void CloseContents(content::WebContents* source) override;
  void NavigationStateChanged(content::WebContents* source,
                              content::InvalidateTypes changed_flags) override;
  void LoadingStateChanged(content::WebContents* source,
                           bool should_show_loading_ui) override;
  void EnterFullscreenModeForTab(
      content::RenderFrameHost* requesting_frame,
      const blink::mojom::FullscreenOptions& options) override;
  void ExitFullscreenModeForTab(content::WebContents* source) override;
  bool IsFullscreenForTabOrPending(const content::WebContents* source) override;
  bool HandleKeyboardEvent(content::WebContents* source,
                           const input::NativeWebKeyboardEvent& event) override;
  void RequestMediaAccessPermission(
      content::WebContents* web_contents,
      const content::MediaStreamRequest& request,
      content::MediaResponseCallback callback) override;
  bool CheckMediaAccessPermission(content::RenderFrameHost* render_frame_host,
                                  const url::Origin& security_origin,
                                  blink::mojom::MediaStreamType type) override;
  content::JavaScriptDialogManager* GetJavaScriptDialogManager(
      content::WebContents* source) override;
  void RunFileChooser(content::RenderFrameHost* render_frame_host,
                      scoped_refptr<content::FileSelectListener> listener,
                      const blink::mojom::FileChooserParams& params) override;
  void EnumerateDirectory(content::WebContents* web_contents,
                          scoped_refptr<content::FileSelectListener> listener,
                          const base::FilePath& path) override;
  std::unique_ptr<content::EyeDropper> OpenEyeDropper(
      content::RenderFrameHost* frame,
      content::EyeDropperListener* listener) override;

  // content::WebContentsObserver:
  void LoadProgressChanged(double progress) override;

  // favicon::FaviconDriverObserver:
  void OnFaviconUpdated(favicon::FaviconDriver* favicon_driver,
                        NotificationIconType notification_icon_type,
                        const GURL& icon_url,
                        bool icon_url_changed,
                        const gfx::Image& image) override;

  // web_modal::WebContentsModalDialogManagerDelegate:
  void SetWebContentsBlocked(content::WebContents* web_contents,
                             bool blocked) override;
  web_modal::WebContentsModalDialogHost* GetWebContentsModalDialogHost(
      content::WebContents* web_contents) override;
  bool IsWebContentsVisible(content::WebContents* web_contents) override;

  // web_modal::WebContentsModalDialogHost:
  gfx::NativeView GetHostView() const override;
  gfx::Point GetDialogPosition(const gfx::Size& size) override;
  gfx::Size GetMaximumDialogSize() override;
  void AddObserver(web_modal::ModalDialogHostObserver* observer) override;
  void RemoveObserver(web_modal::ModalDialogHostObserver* observer) override;
  void NotifyPositionRequiresUpdate() override;
  bool PlaceDialog(gfx::NativeWindow dialog, const gfx::Size& size) override;

 private:
  static void OnDevToolsChanged(content::WebContents* inspected);
  void UpdateDevTools();
  void DetachDevToolsDialogs();
  void LayoutContents();

  __weak ACTab* owner_;
  NSView* __strong container_;
  raw_ptr<content::WebContents> devtools_ = nullptr;
  DevToolsContentsResizingStrategy devtools_strategy_;
  base::ObserverList<web_modal::ModalDialogHostObserver> modal_observers_;
  NSObject* __strong frame_observer_;
  std::optional<content::WebContents::ScopedIgnoreInputEvents> input_block_;
  std::optional<content::WebContents::ScopedIgnoreInputEvents>
      devtools_input_block_;
  std::unique_ptr<content::WebContents> contents_;
  bool fullscreen_ = false;
};

}  // namespace argon_core

#endif  // ARGON_CORE_BROWSER_AC_TAB_HOST_H_
