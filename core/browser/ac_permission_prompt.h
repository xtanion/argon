// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef ARGON_CORE_BROWSER_AC_PERMISSION_PROMPT_H_
#define ARGON_CORE_BROWSER_AC_PERMISSION_PROMPT_H_

#include <memory>
#include <optional>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "components/permissions/permission_prompt.h"

@class NSAlert;
@class NSWindow;

namespace content {
class WebContents;
}

namespace argon_core {

// Shows site permission requests as a sheet on the tab's window, since
// Chrome's own prompts anchor to a Browser location bar Argon does not have.
class ACPermissionPrompt : public permissions::PermissionPrompt {
 public:
  static std::unique_ptr<permissions::PermissionPrompt> Create(
      content::WebContents* web_contents,
      Delegate* delegate);

  ACPermissionPrompt(NSAlert* alert, Delegate* delegate);
  ACPermissionPrompt(const ACPermissionPrompt&) = delete;
  ACPermissionPrompt& operator=(const ACPermissionPrompt&) = delete;
  ~ACPermissionPrompt() override;

  // permissions::PermissionPrompt:
  bool UpdateAnchor() override;
  TabSwitchingBehavior GetTabSwitchingBehavior() override;
  permissions::PermissionPromptDisposition GetPromptDisposition()
      const override;
  bool IsAskPrompt() const override;
  std::optional<gfx::Rect> GetViewBoundsInScreen() const override;
  std::vector<permissions::ElementAnchoredBubbleVariant> GetPromptVariants()
      const override;
  std::optional<permissions::feature_params::PermissionElementPromptPosition>
  GetPromptPosition() const override;

 private:
  void Show(NSWindow* window);
  void OnResponse(long response);

  NSAlert* __strong alert_;
  raw_ptr<Delegate> delegate_;
  bool responded_ = false;
  base::WeakPtrFactory<ACPermissionPrompt> weak_factory_{this};
};

}  // namespace argon_core

#endif  // ARGON_CORE_BROWSER_AC_PERMISSION_PROMPT_H_
