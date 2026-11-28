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
#import "argon_core/public/ACTab.h"

@interface ACPasswordOffer ()
- (instancetype)initWithSite:(NSString*)site
                    username:(NSString*)username
                      update:(BOOL)update
                          ui:(base::WeakPtr<argon_core::ACPasswordsUI>)ui
    NS_DESIGNATED_INITIALIZER;
- (void)withdraw;
@end

@implementation ACPasswordOffer {
  base::WeakPtr<argon_core::ACPasswordsUI> _ui;
}

@synthesize site = _site;
@synthesize username = _username;
@synthesize update = _update;
@synthesize pending = _pending;

- (instancetype)initWithSite:(NSString*)site
                    username:(NSString*)username
                      update:(BOOL)update
                          ui:(base::WeakPtr<argon_core::ACPasswordsUI>)ui {
  if ((self = [super init])) {
    _site = [site copy];
    _username = [username copy];
    _update = update;
    _pending = YES;
    _ui = ui;
  }
  return self;
}

- (void)withdraw {
  _pending = NO;
}

- (void)answer:(long)response {
  if (!_pending) {
    return;
  }
  _pending = NO;
  if (_ui) {
    _ui->Respond(self, response);
  }
}

- (void)save {
  [self answer:NSAlertFirstButtonReturn];
}

- (void)notNow {
  [self answer:NSAlertSecondButtonReturn];
}

- (void)neverForThisSite {
  if (!_update) {
    [self answer:NSAlertThirdButtonReturn];
  }
}

@end

namespace argon_core {

namespace {

PasswordsClientUIDelegate* Lookup(content::WebContents* web_contents) {
  return ACPasswordsUI::FromWebContents(web_contents);
}

}  // namespace

ACPasswordsUI::ACPasswordsUI(content::WebContents* web_contents, ACTab* owner)
    : content::WebContentsUserData<ACPasswordsUI>(*web_contents),
      owner_(owner) {}

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
  pending_ = std::move(form_manager);
  pending_is_update_ = update;

  NSString* site = base::SysUTF16ToNSString(
      url_formatter::FormatUrlForSecurityDisplay(
          pending_->GetURL(),
          url_formatter::SchemeDisplay::OMIT_HTTP_AND_HTTPS));
  NSString* username = base::SysUTF16ToNSString(
      GetDisplayUsername(pending_->GetPendingCredentials()));

  ACTab* tab = owner_;
  id<ACTabDelegate> delegate = tab.delegate;
  if ([delegate respondsToSelector:@selector(tab:didOfferPassword:)]) {
    offer_ = [[ACPasswordOffer alloc] initWithSite:site
                                          username:username
                                            update:update
                                                ui:weak_factory_.GetWeakPtr()];
    [delegate tab:tab didOfferPassword:offer_];
    return;
  }
  ShowAlert(site, username);
}

void ACPasswordsUI::ShowAlert(NSString* site, NSString* username) {
  NSWindow* window =
      GetWebContents().GetNativeView().GetNativeNSView().window;
  if (!window || window.attachedSheet) {
    pending_.reset();
    return;
  }
  bool update = pending_is_update_;
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

void ACPasswordsUI::Respond(ACPasswordOffer* offer, long response) {
  if (offer != offer_) {
    return;
  }
  offer_ = nil;
  OnResponse(response);
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
  if (ACPasswordOffer* offer = offer_) {
    offer_ = nil;
    [offer withdraw];
    ACTab* tab = owner_;
    id<ACTabDelegate> delegate = tab.delegate;
    if ([delegate respondsToSelector:@selector(tab:didWithdrawPasswordOffer:)]) {
      [delegate tab:tab didWithdrawPasswordOffer:offer];
    }
  }
  NSAlert* alert = alert_;
  alert_ = nil;
  NSWindow* sheet = alert.window;
  if (sheet.sheetParent) {
    [sheet.sheetParent endSheet:sheet];
  }
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(ACPasswordsUI);

}  // namespace argon_core
