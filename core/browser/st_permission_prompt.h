// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef STONE_CORE_BROWSER_ST_PERMISSION_PROMPT_H_
#define STONE_CORE_BROWSER_ST_PERMISSION_PROMPT_H_

#include <memory>
#include <optional>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "components/permissions/permission_prompt.h"

@class STPermissionRequest;
@class STTab;
@class NSAlert;
@class NSWindow;

namespace content {
class WebContents;
}

namespace stone_core {

// Hands site permission requests to the tab's delegate, which draws its own
// prompt, or shows them as a sheet on the tab's window when the delegate does
// not take them. Chrome's own prompts anchor to a Browser location bar Stone
// does not have.
class STPermissionPrompt : public permissions::PermissionPrompt {
 public:
  enum class Answer { kAllow, kAllowThisTime, kBlock, kNotNow, kSettings };

  static std::unique_ptr<permissions::PermissionPrompt> Create(
      STTab* tab,
      content::WebContents* web_contents,
      Delegate* delegate);

  STPermissionPrompt(STTab* tab,
                     Delegate* delegate,
                     content::WebContents* web_contents,
                     std::optional<ContentSettingsType> system_blocked);
  STPermissionPrompt(const STPermissionPrompt&) = delete;
  STPermissionPrompt& operator=(const STPermissionPrompt&) = delete;
  ~STPermissionPrompt() override;

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

  __weak STTab* tab_ = nil;
  STPermissionRequest* __strong request_ = nil;
  NSAlert* __strong alert_ = nil;
  raw_ptr<Delegate> delegate_;
  raw_ptr<content::WebContents> web_contents_;
  std::optional<ContentSettingsType> system_blocked_;
  bool responded_ = false;
  base::WeakPtrFactory<STPermissionPrompt> weak_factory_{this};
};

}  // namespace stone_core

#endif  // STONE_CORE_BROWSER_ST_PERMISSION_PROMPT_H_
