// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#import "stone_core/browser/st_passwords_ui.h"

#import <AppKit/AppKit.h>

#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/ui/passwords/ui_utils.h"
#include "components/password_manager/core/browser/password_form.h"
#include "components/password_manager/core/browser/password_form_manager_for_ui.h"
#include "components/url_formatter/elide_url.h"
#include "content/public/browser/web_contents.h"
#import "stone_core/public/STTab.h"

@interface STPasswordOffer ()
- (instancetype)initWithSite:(NSString*)site
                    username:(NSString*)username
                      update:(BOOL)update
                          ui:(base::WeakPtr<stone_core::STPasswordsUI>)ui
    NS_DESIGNATED_INITIALIZER;
- (void)withdraw;
@end

@implementation STPasswordOffer {
  base::WeakPtr<stone_core::STPasswordsUI> _ui;
}

@synthesize site = _site;
@synthesize username = _username;
@synthesize update = _update;
@synthesize pending = _pending;

- (instancetype)initWithSite:(NSString*)site
                    username:(NSString*)username
                      update:(BOOL)update
                          ui:(base::WeakPtr<stone_core::STPasswordsUI>)ui {
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

namespace stone_core {

namespace {

PasswordsClientUIDelegate* Lookup(content::WebContents* web_contents) {
  return STPasswordsUI::FromWebContents(web_contents);
}

}  // namespace

STPasswordsUI::STPasswordsUI(content::WebContents* web_contents, STTab* owner)
    : content::WebContentsUserData<STPasswordsUI>(*web_contents),
      owner_(owner) {}

STPasswordsUI::~STPasswordsUI() {
  Dismiss();
}

// static
void STPasswordsUI::Install() {
  SetExternalPasswordsClientUIDelegateLookup(&Lookup);
}

void STPasswordsUI::OnPasswordSubmitted(
    std::unique_ptr<password_manager::PasswordFormManagerForUI> form_manager) {
  Offer(std::move(form_manager), /*update=*/false);
}

void STPasswordsUI::OnUpdatePasswordSubmitted(
    std::unique_ptr<password_manager::PasswordFormManagerForUI> form_manager) {
  Offer(std::move(form_manager), /*update=*/true);
}

bool STPasswordsUI::OnChooseCredentials(
    std::vector<std::unique_ptr<password_manager::PasswordForm>>
        local_credentials,
    const url::Origin& origin,
    base::OnceCallback<void(const password_manager::PasswordForm*)> callback) {
  std::move(callback).Run(nullptr);
  return true;
}

void STPasswordsUI::Offer(
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

  STTab* tab = owner_;
  id<STTabDelegate> delegate = tab.delegate;
  if ([delegate respondsToSelector:@selector(tab:didOfferPassword:)]) {
    offer_ = [[STPasswordOffer alloc] initWithSite:site
                                          username:username
                                            update:update
                                                ui:weak_factory_.GetWeakPtr()];
    [delegate tab:tab didOfferPassword:offer_];
    return;
  }
  ShowAlert(site, username);
}

void STPasswordsUI::ShowAlert(NSString* site, NSString* username) {
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

  base::WeakPtr<STPasswordsUI> weak = weak_factory_.GetWeakPtr();
  [alert_ beginSheetModalForWindow:window
                 completionHandler:^(NSModalResponse response) {
                   if (weak) {
                     weak->OnResponse(response);
                   }
                 }];
}

void STPasswordsUI::Respond(STPasswordOffer* offer, long response) {
  if (offer != offer_) {
    return;
  }
  offer_ = nil;
  OnResponse(response);
}

void STPasswordsUI::OnResponse(long response) {
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

void STPasswordsUI::Dismiss() {
  pending_.reset();
  if (STPasswordOffer* offer = offer_) {
    offer_ = nil;
    [offer withdraw];
    STTab* tab = owner_;
    id<STTabDelegate> delegate = tab.delegate;
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

WEB_CONTENTS_USER_DATA_KEY_IMPL(STPasswordsUI);

}  // namespace stone_core
