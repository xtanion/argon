// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#import "argon_core/browser/ac_permission_prompt.h"

#import <AppKit/AppKit.h>

#include "base/strings/sys_string_conversions.h"
#include "components/permissions/permission_request.h"
#include "components/permissions/permission_uma_util.h"
#include "components/permissions/resolvers/permission_prompt_options.h"
#include "components/url_formatter/elide_url.h"
#include "content/public/browser/web_contents.h"

namespace argon_core {

namespace {

NSString* MessageFor(permissions::PermissionPrompt::Delegate* delegate) {
  NSMutableArray<NSString*>* lines = [NSMutableArray array];
  for (const auto& request : delegate->Requests()) {
    NSString* line = base::SysUTF16ToNSString(request->GetMessageTextFragment());
    if (line.length && ![lines containsObject:line]) {
      [lines addObject:line];
    }
  }
  return [lines componentsJoinedByString:@"\n"];
}

}  // namespace

std::unique_ptr<permissions::PermissionPrompt> ACPermissionPrompt::Create(
    content::WebContents* web_contents,
    Delegate* delegate) {
  NSWindow* window =
      web_contents->GetNativeView().GetNativeNSView().window;
  if (!window || delegate->Requests().empty()) {
    return nullptr;
  }

  NSAlert* alert = [[NSAlert alloc] init];
  alert.messageText = [NSString
      stringWithFormat:@"%@ wants to",
                       base::SysUTF16ToNSString(
                           url_formatter::FormatUrlForSecurityDisplay(
                               delegate->GetRequestingOrigin(),
                               url_formatter::SchemeDisplay::
                                   OMIT_CRYPTOGRAPHIC))];
  alert.informativeText = MessageFor(delegate);
  [alert addButtonWithTitle:@"Allow"];
  [alert addButtonWithTitle:@"Allow This Time"];
  [alert addButtonWithTitle:@"Block"];
  alert.buttons[2].keyEquivalent = @"\e";

  auto prompt = std::make_unique<ACPermissionPrompt>(alert, delegate);
  prompt->Show(window);
  return prompt;
}

ACPermissionPrompt::ACPermissionPrompt(NSAlert* alert, Delegate* delegate)
    : alert_(alert), delegate_(delegate) {}

ACPermissionPrompt::~ACPermissionPrompt() {
  responded_ = true;
  NSWindow* sheet = alert_.window;
  if (sheet.sheetParent) {
    [sheet.sheetParent endSheet:sheet];
  }
}

void ACPermissionPrompt::Show(NSWindow* window) {
  delegate_->SetPromptShown();
  base::WeakPtr<ACPermissionPrompt> weak = weak_factory_.GetWeakPtr();
  [alert_ beginSheetModalForWindow:window
                 completionHandler:^(NSModalResponse response) {
                   if (weak) {
                     weak->OnResponse(response);
                   }
                 }];
}

// The delegate destroys this prompt synchronously from each decision call.
void ACPermissionPrompt::OnResponse(long response) {
  if (responded_) {
    return;
  }
  responded_ = true;
  Delegate* delegate = delegate_;
  delegate->SetDecisionTime();
  PromptOptions options = std::monostate();
  switch (response) {
    case NSAlertFirstButtonReturn:
      delegate->Accept(options);
      break;
    case NSAlertSecondButtonReturn:
      delegate->AcceptThisTime(options);
      break;
    case NSAlertThirdButtonReturn:
      delegate->Deny(options);
      break;
    default:
      delegate->Dismiss(options);
      break;
  }
}

bool ACPermissionPrompt::UpdateAnchor() {
  return true;
}

permissions::PermissionPrompt::TabSwitchingBehavior
ACPermissionPrompt::GetTabSwitchingBehavior() {
  return kDestroyPromptButKeepRequestPending;
}

permissions::PermissionPromptDisposition
ACPermissionPrompt::GetPromptDisposition() const {
  return permissions::PermissionPromptDisposition::CUSTOM_MODAL_DIALOG;
}

bool ACPermissionPrompt::IsAskPrompt() const {
  return true;
}

std::optional<gfx::Rect> ACPermissionPrompt::GetViewBoundsInScreen() const {
  return std::nullopt;
}

std::vector<permissions::ElementAnchoredBubbleVariant>
ACPermissionPrompt::GetPromptVariants() const {
  return {};
}

std::optional<permissions::feature_params::PermissionElementPromptPosition>
ACPermissionPrompt::GetPromptPosition() const {
  return std::nullopt;
}

}  // namespace argon_core
