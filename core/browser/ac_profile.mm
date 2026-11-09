// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#import "argon_core/browser/ac_internal.h"

#include <memory>

#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/download/download_core_service.h"
#include "chrome/browser/download/download_core_service_factory.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/search_engines/template_url_service_factory.h"
#include "components/download/content/public/all_download_item_notifier.h"
#include "components/download/public/common/download_item.h"
#include "components/search_engines/template_url.h"
#include "components/search_engines/template_url_service.h"
#include "content/public/browser/download_manager.h"
#include "content/public/browser/web_contents.h"
#include "net/base/apple/url_conversions.h"

@interface ACProfile ()
- (void)downloadAdded:(download::DownloadItem*)item;
- (void)downloadUpdated:(download::DownloadItem*)item;
- (void)downloadGone:(download::DownloadItem*)item;
@end

namespace {

class DownloadObserver : public download::AllDownloadItemNotifier::Observer {
 public:
  DownloadObserver(ACProfile* owner, content::DownloadManager* manager)
      : owner_(owner), notifier_(manager, this) {}

  void OnDownloadCreated(content::DownloadManager* manager,
                         download::DownloadItem* item) override {
    [owner_ downloadAdded:item];
  }
  void OnDownloadUpdated(content::DownloadManager* manager,
                         download::DownloadItem* item) override {
    [owner_ downloadUpdated:item];
  }
  void OnDownloadRemoved(content::DownloadManager* manager,
                         download::DownloadItem* item) override {
    [owner_ downloadGone:item];
  }
  void OnDownloadDestroyed(content::DownloadManager* manager,
                           download::DownloadItem* item) override {
    [owner_ downloadGone:item];
  }

 private:
  __weak ACProfile* owner_;
  download::AllDownloadItemNotifier notifier_;
};

}  // namespace

@implementation ACProfile {
  raw_ptr<Profile> _profile;
  std::unique_ptr<ScopedProfileKeepAlive> _keepAlive;
  std::unique_ptr<DownloadObserver> _downloadObserver;
  NSMutableArray<ACDownload*>* _downloads;
  NSMutableDictionary<NSString*, ACDownload*>* _downloadsByGuid;
}

@synthesize downloadDelegate = _downloadDelegate;

- (instancetype)initWithProfile:(Profile*)profile {
  self = [super init];
  if (self) {
    _profile = profile;
    if (!profile->IsOffTheRecord()) {
      _keepAlive = std::make_unique<ScopedProfileKeepAlive>(
          profile, ProfileKeepAliveOrigin::kBrowserWindow);
    }
  }
  return self;
}

- (void)profileWillBeDestroyed {
  _downloadObserver.reset();
  _keepAlive.reset();
  _profile = nullptr;
}

- (Profile*)nativeProfile {
  CHECK(_profile);
  return _profile;
}

- (NSString*)identifier {
  return base::SysUTF8ToNSString(
      self.nativeProfile->GetBaseName().AsUTF8Unsafe());
}

- (NSString*)displayName {
  return base::SysUTF8ToNSString(self.nativeProfile->GetProfileUserName());
}

- (const TemplateURL*)defaultSearchProvider {
  TemplateURLService* service =
      TemplateURLServiceFactory::GetForProfile(self.nativeProfile);
  if (!service) {
    return nullptr;
  }
  service->Load();
  return service->GetDefaultSearchProvider();
}

- (NSString*)searchEngineName {
  const TemplateURL* provider = [self defaultSearchProvider];
  return provider ? base::SysUTF16ToNSString(provider->short_name()) : nil;
}

- (NSURL*)searchURLForQuery:(NSString*)query {
  const TemplateURL* provider = [self defaultSearchProvider];
  if (!provider) {
    return nil;
  }
  TemplateURLService* service =
      TemplateURLServiceFactory::GetForProfile(self.nativeProfile);
  GURL url(provider->url_ref().ReplaceSearchTerms(
      TemplateURLRef::SearchTermsArgs(base::SysNSStringToUTF16(query)),
      service->search_terms_data()));
  return url.is_valid() ? net::NSURLWithGURL(url) : nil;
}

- (BOOL)isOffTheRecord {
  return self.nativeProfile->IsOffTheRecord();
}

- (void)startObservingDownloads {
  if (_downloadObserver || !_profile) {
    return;
  }
  _downloads = [NSMutableArray array];
  _downloadsByGuid = [NSMutableDictionary dictionary];
  content::DownloadManager::DownloadVector items;
  content::DownloadManager* manager = _profile->GetDownloadManager();
  manager->GetAllDownloads(&items);
  _downloadObserver = std::make_unique<DownloadObserver>(self, manager);
  for (download::DownloadItem* item : items) {
    [self trackItem:item isNew:NO notify:NO];
  }
  // History loading is deferred until some UI asks for it; past downloads then
  // arrive through OnDownloadCreated.
  if (DownloadCoreService* service =
          DownloadCoreServiceFactory::GetForBrowserContext(_profile)) {
    service->InitializeHistory(
        DownloadCoreService::DownloadHistoryLoadTrigger::kDownloadBubble);
  }
}

- (void)setDownloadDelegate:(id<ACProfileDownloadDelegate>)delegate {
  _downloadDelegate = delegate;
  if (delegate) {
    [self startObservingDownloads];
  }
}

- (NSArray<ACDownload*>*)downloads {
  [self startObservingDownloads];
  NSArray* sorted = [_downloads
      sortedArrayUsingComparator:^NSComparisonResult(ACDownload* a,
                                                     ACDownload* b) {
        return [b.startDate compare:a.startDate];
      }];
  return sorted ?: @[];
}

- (void)trackItem:(download::DownloadItem*)item
            isNew:(BOOL)isNew
           notify:(BOOL)notify {
  if (item->IsTransient() || item->IsTemporary()) {
    return;
  }
  NSString* guid = base::SysUTF8ToNSString(item->GetGuid());
  if (_downloadsByGuid[guid]) {
    return;
  }
  ACDownload* download = [[ACDownload alloc] initWithItem:item];
  _downloadsByGuid[guid] = download;
  [_downloads addObject:download];
  if (notify && [_downloadDelegate respondsToSelector:@selector
                                   (profile:didAddDownload:isNew:)]) {
    [_downloadDelegate profile:self didAddDownload:download isNew:isNew];
  }
}

- (void)downloadAdded:(download::DownloadItem*)item {
  BOOL isNew = item->GetState() == download::DownloadItem::IN_PROGRESS;
  [self trackItem:item isNew:isNew notify:YES];
}

- (void)downloadUpdated:(download::DownloadItem*)item {
  ACDownload* download =
      _downloadsByGuid[base::SysUTF8ToNSString(item->GetGuid())];
  if (!download) {
    [self downloadAdded:item];
    return;
  }
  [download itemUpdated];
  if ([_downloadDelegate
          respondsToSelector:@selector(profile:didUpdateDownload:)]) {
    [_downloadDelegate profile:self didUpdateDownload:download];
  }
}

- (void)downloadGone:(download::DownloadItem*)item {
  NSString* guid = base::SysUTF8ToNSString(item->GetGuid());
  ACDownload* download = _downloadsByGuid[guid];
  if (!download) {
    return;
  }
  [download itemGone];
  [_downloadsByGuid removeObjectForKey:guid];
  [_downloads removeObject:download];
  if ([_downloadDelegate
          respondsToSelector:@selector(profile:didRemoveDownload:)]) {
    [_downloadDelegate profile:self didRemoveDownload:download];
  }
}

- (ACTab*)createTabWithURL:(NSURL*)url {
  content::WebContents::CreateParams params(self.nativeProfile);
  params.initially_hidden = false;
  ACTab* tab = [[ACTab alloc]
      initWithProfile:self
          webContents:content::WebContents::Create(params)];
  if (url) {
    [tab loadURL:url];
  }
  return tab;
}

@end
