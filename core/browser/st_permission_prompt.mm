// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#import "stone_core/browser/st_permission_prompt.h"

#import <AppKit/AppKit.h>

#import "stone_core/public/STTab.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/permissions/system/system_permission_settings.h"
#include "components/permissions/permission_request.h"
#include "components/permissions/permission_uma_util.h"
#include "components/permissions/resolvers/permission_prompt_options.h"
#include "components/url_formatter/elide_url.h"
#include "content/public/browser/web_contents.h"

using stone_core::STPermissionPrompt;

@interface STPermissionRequest ()
- (instancetype)initWithSite:(NSString*)site
                       kinds:(STPermissionKinds)kinds
                descriptions:(NSArray<NSString*>*)descriptions
             blockedBySystem:(STPermissionKinds)blockedBySystem
                      prompt:(base::WeakPtr<STPermissionPrompt>)prompt
    NS_DESIGNATED_INITIALIZER;
- (void)withdraw;
@end

@implementation STPermissionRequest {
  base::WeakPtr<STPermissionPrompt> _prompt;
}

@synthesize site = _site;
@synthesize kinds = _kinds;
@synthesize descriptions = _descriptions;
@synthesize blockedBySystem = _blockedBySystem;
@synthesize pending = _pending;

- (instancetype)initWithSite:(NSString*)site
                       kinds:(STPermissionKinds)kinds
                descriptions:(NSArray<NSString*>*)descriptions
             blockedBySystem:(STPermissionKinds)blockedBySystem
                      prompt:(base::WeakPtr<STPermissionPrompt>)prompt {
  if ((self = [super init])) {
    _site = [site copy];
    _kinds = kinds;
    _descriptions = [descriptions copy];
    _blockedBySystem = blockedBySystem;
    _pending = YES;
    _prompt = prompt;
  }
  return self;
}

- (void)withdraw {
  _pending = NO;
}

- (void)answer:(STPermissionPrompt::Answer)answer {
  if (!_pending) {
    return;
  }
  _pending = NO;
  if (_prompt) {
    _prompt->Respond(answer);
  }
}

- (void)allow {
  [self answer:STPermissionPrompt::Answer::kAllow];
}

- (void)allowThisTime {
  [self answer:STPermissionPrompt::Answer::kAllowThisTime];
}

- (void)block {
  [self answer:STPermissionPrompt::Answer::kBlock];
}

- (void)notNow {
  [self answer:STPermissionPrompt::Answer::kNotNow];
}

- (void)openSystemSettings {
  [self answer:STPermissionPrompt::Answer::kSettings];
}

@end

namespace stone_core {

namespace {

STPermissionKinds KindFor(ContentSettingsType type) {
  switch (type) {
    case ContentSettingsType::MEDIASTREAM_CAMERA:
    case ContentSettingsType::CAMERA_PAN_TILT_ZOOM:
      return STPermissionKindCamera;
    case ContentSettingsType::MEDIASTREAM_MIC:
      return STPermissionKindMicrophone;
    case ContentSettingsType::GEOLOCATION:
    case ContentSettingsType::GEOLOCATION_WITH_OPTIONS:
      return STPermissionKindLocation;
    case ContentSettingsType::NOTIFICATIONS:
      return STPermissionKindNotifications;
    default:
      return STPermissionKindOther;
  }
}

NSString* SystemName(ContentSettingsType type) {
  switch (KindFor(type)) {
    case STPermissionKindCamera:
      return @"the camera";
    case STPermissionKindMicrophone:
      return @"the microphone";
    case STPermissionKindLocation:
      return @"your location";
    case STPermissionKindNotifications:
      return @"notifications";
    default:
      return @"this";
  }
}

NSArray<NSString*>* DescriptionsFor(
    permissions::PermissionPrompt::Delegate* delegate) {
  NSMutableArray<NSString*>* lines = [NSMutableArray array];
  for (const auto& request : delegate->Requests()) {
    NSString* line =
        base::SysUTF16ToNSString(request->GetMessageTextFragment());
    if (line.length && ![lines containsObject:line]) {
      [lines addObject:line];
    }
  }
  return lines;
}

NSString* SiteFor(permissions::PermissionPrompt::Delegate* delegate) {
  return base::SysUTF16ToNSString(url_formatter::FormatUrlForSecurityDisplay(
      delegate->GetRequestingOrigin(),
      url_formatter::SchemeDisplay::OMIT_CRYPTOGRAPHIC));
}

}  // namespace

std::unique_ptr<permissions::PermissionPrompt> STPermissionPrompt::Create(
    STTab* tab,
    content::WebContents* web_contents,
    Delegate* delegate) {
  if (delegate->Requests().empty()) {
    return nullptr;
  }
  std::optional<ContentSettingsType> blocked;
  for (const auto& request : delegate->Requests()) {
    ContentSettingsType type = request->GetContentSettingsType();
    if (type != ContentSettingsType::DEFAULT &&
        system_permission_settings::IsDenied(type)) {
      blocked = type;
      break;
    }
  }
  auto prompt = std::make_unique<STPermissionPrompt>(tab, delegate,
                                                     web_contents, blocked);
  id<STTabDelegate> tab_delegate = tab.delegate;
  if ([tab_delegate respondsToSelector:@selector(tab:didRequestPermission:)]) {
    prompt->Offer();
    return prompt;
  }
  NSWindow* window = web_contents->GetNativeView().GetNativeNSView().window;
  if (!window) {
    return nullptr;
  }
  prompt->ShowAlert(window);
  return prompt;
}

STPermissionPrompt::STPermissionPrompt(
    STTab* tab,
    Delegate* delegate,
    content::WebContents* web_contents,
    std::optional<ContentSettingsType> system_blocked)
    : tab_(tab),
      delegate_(delegate),
      web_contents_(web_contents),
      system_blocked_(system_blocked) {}

STPermissionPrompt::~STPermissionPrompt() {
  responded_ = true;
  if (STPermissionRequest* request = request_; request.pending) {
    [request withdraw];
    STTab* tab = tab_;
    id<STTabDelegate> delegate = tab.delegate;
    if ([delegate respondsToSelector:@selector(tab:
                                         didWithdrawPermissionRequest:)]) {
      [delegate tab:tab didWithdrawPermissionRequest:request];
    }
  }
  NSWindow* sheet = alert_.window;
  if (sheet.sheetParent) {
    [sheet.sheetParent endSheet:sheet];
  }
}

void STPermissionPrompt::Offer() {
  STPermissionKinds kinds = 0;
  STPermissionKinds blocked = 0;
  for (const auto& request : delegate_->Requests()) {
    ContentSettingsType type = request->GetContentSettingsType();
    kinds |= KindFor(type);
    if (type != ContentSettingsType::DEFAULT &&
        system_permission_settings::IsDenied(type)) {
      blocked |= KindFor(type);
    }
  }
  request_ = [[STPermissionRequest alloc]
         initWithSite:SiteFor(delegate_)
                kinds:kinds
         descriptions:DescriptionsFor(delegate_)
      blockedBySystem:blocked
               prompt:weak_factory_.GetWeakPtr()];
  delegate_->SetPromptShown();
  STTab* tab = tab_;
  [tab.delegate tab:tab didRequestPermission:request_];
}

void STPermissionPrompt::ShowAlert(NSWindow* window) {
  NSString* site = SiteFor(delegate_);
  alert_ = [[NSAlert alloc] init];
  if (system_blocked_) {
    NSString* name = SystemName(*system_blocked_);
    alert_.messageText =
        [NSString stringWithFormat:@"%@ wants to use %@", site, name];
    alert_.informativeText = [NSString
        stringWithFormat:@"macOS doesn't allow Stone to use %@. Turn it on "
                         @"for Stone in System Settings, then reload the page.",
                         name];
    [alert_ addButtonWithTitle:@"Open System Settings"];
    [alert_ addButtonWithTitle:@"Not Now"];
    alert_.buttons[1].keyEquivalent = @"\e";
  } else {
    alert_.messageText = [NSString stringWithFormat:@"%@ wants to", site];
    alert_.informativeText =
        [DescriptionsFor(delegate_) componentsJoinedByString:@"\n"];
    [alert_ addButtonWithTitle:@"Allow"];
    [alert_ addButtonWithTitle:@"Allow This Time"];
    [alert_ addButtonWithTitle:@"Block"];
    alert_.buttons[2].keyEquivalent = @"\e";
  }

  delegate_->SetPromptShown();
  base::WeakPtr<STPermissionPrompt> weak = weak_factory_.GetWeakPtr();
  bool blocked = system_blocked_.has_value();
  [alert_ beginSheetModalForWindow:window
                 completionHandler:^(NSModalResponse response) {
                   if (!weak) {
                     return;
                   }
                   if (blocked) {
                     weak->Respond(response == NSAlertFirstButtonReturn
                                       ? Answer::kSettings
                                       : Answer::kNotNow);
                     return;
                   }
                   switch (response) {
                     case NSAlertFirstButtonReturn:
                       weak->Respond(Answer::kAllow);
                       break;
                     case NSAlertSecondButtonReturn:
                       weak->Respond(Answer::kAllowThisTime);
                       break;
                     case NSAlertThirdButtonReturn:
                       weak->Respond(Answer::kBlock);
                       break;
                     default:
                       weak->Respond(Answer::kNotNow);
                       break;
                   }
                 }];
}

// The delegate destroys this prompt synchronously from each decision call, so
// nothing may touch members after it.
void STPermissionPrompt::Respond(Answer answer) {
  if (responded_) {
    return;
  }
  responded_ = true;
  Delegate* delegate = delegate_;
  content::WebContents* web_contents = web_contents_;
  std::optional<ContentSettingsType> blocked = system_blocked_;
  delegate->SetDecisionTime();
  PromptOptions options = std::monostate();
  switch (answer) {
    case Answer::kAllow:
      delegate->Accept(options);
      break;
    case Answer::kAllowThisTime:
      delegate->AcceptThisTime(options);
      break;
    case Answer::kBlock:
      delegate->Deny(options);
      break;
    case Answer::kNotNow:
      delegate->Dismiss(options);
      break;
    case Answer::kSettings:
      if (blocked) {
        system_permission_settings::OpenSystemSettings(web_contents, *blocked);
      }
      delegate->Ignore(options);
      break;
  }
}

bool STPermissionPrompt::UpdateAnchor() {
  return true;
}

permissions::PermissionPrompt::TabSwitchingBehavior
STPermissionPrompt::GetTabSwitchingBehavior() {
  return kDestroyPromptButKeepRequestPending;
}

permissions::PermissionPromptDisposition
STPermissionPrompt::GetPromptDisposition() const {
  return permissions::PermissionPromptDisposition::CUSTOM_MODAL_DIALOG;
}

bool STPermissionPrompt::IsAskPrompt() const {
  return true;
}

std::optional<gfx::Rect> STPermissionPrompt::GetViewBoundsInScreen() const {
  return std::nullopt;
}

std::vector<permissions::ElementAnchoredBubbleVariant>
STPermissionPrompt::GetPromptVariants() const {
  return {};
}

std::optional<permissions::feature_params::PermissionElementPromptPosition>
STPermissionPrompt::GetPromptPosition() const {
  return std::nullopt;
}

}  // namespace stone_core
