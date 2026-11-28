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
#include "components/content_settings/core/common/content_settings_types.h"
#include "components/permissions/permission_prompt.h"

@class ACPermissionRequest;
@class ACTab;
@class NSAlert;
@class NSWindow;

namespace content {
class WebContents;
}

namespace argon_core {

// Hands site permission requests to the tab's delegate, which draws its own
// prompt, or shows them as a sheet on the tab's window when the delegate does
// not take them. Chrome's own prompts anchor to a Browser location bar Argon
// does not have.
class ACPermissionPrompt : public permissions::PermissionPrompt {
 public:
  enum class Answer { kAllow, kAllowThisTime, kBlock, kNotNow, kSettings };

  static std::unique_ptr<permissions::PermissionPrompt> Create(
      ACTab* tab,
      content::WebContents* web_contents,
      Delegate* delegate);

  ACPermissionPrompt(ACTab* tab,
                     Delegate* delegate,
                     content::WebContents* web_contents,
                     std::optional<ContentSettingsType> system_blocked);
  ACPermissionPrompt(const ACPermissionPrompt&) = delete;
  ACPermissionPrompt& operator=(const ACPermissionPrompt&) = delete;
  ~ACPermissionPrompt() override;

  void Respond(Answer answer);

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
  void Offer();
  void ShowAlert(NSWindow* window);

  __weak ACTab* tab_ = nil;
  ACPermissionRequest* __strong request_ = nil;
  NSAlert* __strong alert_ = nil;
  raw_ptr<Delegate> delegate_;
  raw_ptr<content::WebContents> web_contents_;
  std::optional<ContentSettingsType> system_blocked_;
  bool responded_ = false;
  base::WeakPtrFactory<ACPermissionPrompt> weak_factory_{this};
};

}  // namespace argon_core

#endif  // ARGON_CORE_BROWSER_AC_PERMISSION_PROMPT_H_
