// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#import "argon_core/browser/ac_passwords_ui.h"

#import <AppKit/AppKit.h>

#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/ui/passwords/ui_utils.h"
#include "components/password_manager/core/browser/password_form.h"
#include "components/password_manager/core/browser/password_form_manager_for_ui.h"
#include "components/url_formatter/elide_url.h"
#include "content/public/browser/web_contents.h"

namespace argon_core {

namespace {

PasswordsClientUIDelegate* Lookup(content::WebContents* web_contents) {
  return ACPasswordsUI::FromWebContents(web_contents);
}

}  // namespace

ACPasswordsUI::ACPasswordsUI(content::WebContents* web_contents)
    : content::WebContentsUserData<ACPasswordsUI>(*web_contents) {}

ACPasswordsUI::~ACPasswordsUI() {
  Dismiss();
}

// static
void ACPasswordsUI::Install() {
  SetExternalPasswordsClientUIDelegateLookup(&Lookup);
}

void ACPasswordsUI::OnPasswordSubmitted(
    std::unique_ptr<password_manager::PasswordFormManagerForUI> form_manager) {
  Offer(std::move(form_manager), /*update=*/false);
}

void ACPasswordsUI::OnUpdatePasswordSubmitted(
    std::unique_ptr<password_manager::PasswordFormManagerForUI> form_manager) {
  Offer(std::move(form_manager), /*update=*/true);
}

bool ACPasswordsUI::OnChooseCredentials(
    std::vector<std::unique_ptr<password_manager::PasswordForm>>
        local_credentials,
    const url::Origin& origin,
    base::OnceCallback<void(const password_manager::PasswordForm*)> callback) {
  std::move(callback).Run(nullptr);
  return true;
}

void ACPasswordsUI::Offer(
    std::unique_ptr<password_manager::PasswordFormManagerForUI> form_manager,
    bool update) {
  Dismiss();
  NSWindow* window =
      GetWebContents().GetNativeView().GetNativeNSView().window;
  if (!window || window.attachedSheet) {
    return;
  }
  pending_ = std::move(form_manager);
  pending_is_update_ = update;

  NSString* site = base::SysUTF16ToNSString(
      url_formatter::FormatUrlForSecurityDisplay(
          pending_->GetURL(),
          url_formatter::SchemeDisplay::OMIT_HTTP_AND_HTTPS));
  NSString* username = base::SysUTF16ToNSString(
      GetDisplayUsername(pending_->GetPendingCredentials()));

  alert_ = [[NSAlert alloc] init];
  alert_.messageText =
      update ? [NSString stringWithFormat:@"Update password for %@?", site]
             : [NSString stringWithFormat:@"Save password for %@?", site];
  alert_.informativeText = username;
  [alert_ addButtonWithTitle:update ? @"Update" : @"Save"];
  [alert_ addButtonWithTitle:@"Not Now"];
  alert_.buttons[1].keyEquivalent = @"\e";
  if (!update) {
    [alert_ addButtonWithTitle:@"Never for This Site"];
  }

  base::WeakPtr<ACPasswordsUI> weak = weak_factory_.GetWeakPtr();
  [alert_ beginSheetModalForWindow:window
                 completionHandler:^(NSModalResponse response) {
                   if (weak) {
                     weak->OnResponse(response);
                   }
                 }];
}

void ACPasswordsUI::OnResponse(long response) {
  alert_ = nil;
  std::unique_ptr<password_manager::PasswordFormManagerForUI> form_manager =
      std::move(pending_);
  if (!form_manager) {
    return;
  }
  switch (response) {
    case NSAlertFirstButtonReturn:
      form_manager->Save();
      break;
    case NSAlertThirdButtonReturn:
      form_manager->OnNeverClicked();
      break;
    default:
      if (pending_is_update_) {
        form_manager->OnNopeUpdateClicked();
      } else {
        form_manager->OnNoInteraction(/*is_update=*/false);
      }
      break;
  }
}

void ACPasswordsUI::Dismiss() {
  pending_.reset();
  NSAlert* alert = alert_;
  alert_ = nil;
  NSWindow* sheet = alert.window;
  if (sheet.sheetParent) {
    [sheet.sheetParent endSheet:sheet];
  }
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(ACPasswordsUI);

}  // namespace argon_core
