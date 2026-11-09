// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#import "argon_core/public/ACAutocomplete.h"

#include <memory>

#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/cancelable_task_tracker.h"
#include "chrome/browser/autocomplete/chrome_autocomplete_provider_client.h"
#include "chrome/browser/autocomplete/chrome_autocomplete_scheme_classifier.h"
#include "chrome/browser/autocomplete/shortcuts_backend_factory.h"
#include "chrome/browser/favicon/favicon_service_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "components/favicon/core/favicon_service.h"
#include "components/favicon_base/favicon_types.h"
#include "components/keyed_service/core/service_access_type.h"
#include "components/omnibox/browser/autocomplete_controller.h"
#include "components/omnibox/browser/autocomplete_controller_config.h"
#include "components/omnibox/browser/autocomplete_input.h"
#include "components/omnibox/browser/autocomplete_match.h"
#include "components/omnibox/browser/autocomplete_provider.h"
#include "components/omnibox/browser/autocomplete_result.h"
#include "components/omnibox/browser/shortcuts_backend.h"
#include "argon_core/browser/ac_internal.h"
#include "net/base/apple/url_conversions.h"
#include "third_party/metrics_proto/omnibox_event.pb.h"
#include "ui/gfx/image/image.h"

namespace {

using MatchType = omnibox::AutocompleteMatchType;

ACAutocompleteMatchKind KindFor(const AutocompleteMatch& match) {
  switch (match.type) {
    case MatchType::kUrlWhatYouTyped:
      return ACAutocompleteMatchKindURL;
    case MatchType::kHistoryUrl:
    case MatchType::kHistoryTitle:
    case MatchType::kHistoryBody:
    case MatchType::kHistoryKeyword:
    case MatchType::kNavsuggest:
      return ACAutocompleteMatchKindHistory;
    case MatchType::kBookmarkTitle:
      return ACAutocompleteMatchKindBookmark;
    case MatchType::kSearchHistory:
      return ACAutocompleteMatchKindSearchHistory;
    default:
      break;
  }
  if (AutocompleteMatch::IsSearchType(match.type)) {
    return ACAutocompleteMatchKindSearch;
  }
  return match.destination_url.is_valid() ? ACAutocompleteMatchKindHistory
                                          : ACAutocompleteMatchKindOther;
}

int ProviderTypes() {
  return static_cast<int>(AutocompleteProvider::Type::kBookmark |
                          AutocompleteProvider::Type::kBuiltin |
                          AutocompleteProvider::Type::kHistoryQuick |
                          AutocompleteProvider::Type::kHistoryUrl |
                          AutocompleteProvider::Type::kHistoryFuzzy |
                          AutocompleteProvider::Type::kSearch |
                          AutocompleteProvider::Type::kShortcuts |
                          AutocompleteProvider::Type::kCalculator |
                          AutocompleteProvider::Type::kKeyword);
}

}  // namespace

@interface ACAutocompleteMatch ()
- (instancetype)initWithMatch:(const AutocompleteMatch&)match
    NS_DESIGNATED_INITIALIZER;
@property(readonly) const AutocompleteMatch& nativeMatch;
@end

@implementation ACAutocompleteMatch {
  std::unique_ptr<AutocompleteMatch> _match;
}

- (instancetype)initWithMatch:(const AutocompleteMatch&)match {
  self = [super init];
  if (self) {
    _match = std::make_unique<AutocompleteMatch>(match);
  }
  return self;
}

- (const AutocompleteMatch&)nativeMatch {
  return *_match;
}

- (ACAutocompleteMatchKind)kind {
  return KindFor(*_match);
}

- (NSString*)contents {
  return base::SysUTF16ToNSString(_match->contents);
}

- (NSString*)matchDescription {
  return base::SysUTF16ToNSString(_match->description);
}

- (NSString*)fillIntoEdit {
  return base::SysUTF16ToNSString(_match->fill_into_edit);
}

- (NSURL*)destinationURL {
  return _match->destination_url.is_valid()
             ? net::NSURLWithGURL(_match->destination_url)
             : nil;
}

- (NSString*)inlineAutocompletion {
  return base::SysUTF16ToNSString(_match->inline_autocompletion);
}

- (BOOL)allowedToBeDefault {
  return _match->allowed_to_be_default_match;
}

- (int)relevance {
  return _match->relevance;
}

@end

@class ACAutocomplete;

namespace argon_core {

class AutocompleteObserverBridge : public AutocompleteController::Observer {
 public:
  explicit AutocompleteObserverBridge(ACAutocomplete* owner) : owner_(owner) {}

  void OnResultChanged(AutocompleteController* controller,
                       bool default_match_changed) override;

 private:
  __weak ACAutocomplete* owner_;
};

}  // namespace argon_core

@interface ACAutocomplete ()
- (void)resultChanged;
@end

@implementation ACAutocomplete {
  raw_ptr<Profile> _profile;
  std::unique_ptr<AutocompleteController> _controller;
  std::unique_ptr<argon_core::AutocompleteObserverBridge> _observer;
  std::u16string _text;
  base::CancelableTaskTracker _faviconTracker;
  NSArray<ACAutocompleteMatch*>* _matches;
}

@synthesize onResultsChanged = _onResultsChanged;

- (instancetype)initWithProfile:(ACProfile*)profile {
  self = [super init];
  if (self) {
    _profile = profile.nativeProfile;
    _matches = @[];
    _controller = std::make_unique<AutocompleteController>(
        std::make_unique<ChromeAutocompleteProviderClient>(_profile),
        AutocompleteControllerConfig{.provider_types = ProviderTypes()});
    _observer = std::make_unique<argon_core::AutocompleteObserverBridge>(self);
    _controller->AddObserver(_observer.get());
  }
  return self;
}

- (void)dealloc {
  _faviconTracker.TryCancelAll();
  if (_controller) {
    _controller->RemoveObserver(_observer.get());
    _controller->Stop(AutocompleteStopReason::kClobbered);
  }
}

- (NSArray<ACAutocompleteMatch*>*)matches {
  return _matches;
}

- (void)startWithText:(NSString*)text preventInlineAutocomplete:(BOOL)prevent {
  _text = base::SysNSStringToUTF16(text);
  if (_text.empty()) {
    [self stop];
    return;
  }
  AutocompleteInput input(_text, metrics::OmniboxEventProto::OTHER,
                          ChromeAutocompleteSchemeClassifier(_profile));
  input.set_prevent_inline_autocomplete(prevent);
  _controller->Start(input);
}

- (void)stop {
  _controller->Stop(AutocompleteStopReason::kClobbered);
  _matches = @[];
  if (_onResultsChanged) {
    _onResultsChanged(_matches);
  }
}

- (void)resultChanged {
  NSMutableArray<ACAutocompleteMatch*>* matches = [NSMutableArray array];
  for (const AutocompleteMatch& match : _controller->result()) {
    [matches addObject:[[ACAutocompleteMatch alloc] initWithMatch:match]];
  }
  _matches = [matches copy];
  if (_onResultsChanged) {
    _onResultsChanged(_matches);
  }
}

- (void)didOpenMatch:(ACAutocompleteMatch*)match {
  if (_text.empty()) {
    return;
  }
  scoped_refptr<ShortcutsBackend> backend =
      ShortcutsBackendFactory::GetForProfile(_profile);
  if (backend) {
    backend->AddOrUpdateShortcut(_text, match.nativeMatch);
  }
}

- (void)faviconForURL:(NSURL*)url completion:(void (^)(NSImage*))completion {
  favicon::FaviconService* service = FaviconServiceFactory::GetForProfile(
      _profile, ServiceAccessType::EXPLICIT_ACCESS);
  if (!service) {
    completion(nil);
    return;
  }
  void (^callback)(NSImage*) = [completion copy];
  service->GetFaviconImageForPageURL(
      net::GURLWithNSURL(url),
      base::BindOnce(
          [](void (^callback)(NSImage*),
             const favicon_base::FaviconImageResult& result) {
            callback(result.image.IsEmpty() ? nil : result.image.ToNSImage());
          },
          callback),
      &_faviconTracker);
}

@end

namespace argon_core {

void AutocompleteObserverBridge::OnResultChanged(
    AutocompleteController* controller,
    bool default_match_changed) {
  [owner_ resultChanged];
}

}  // namespace argon_core
