// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef STONE_CORE_BROWSER_ST_INTERNAL_H_
#define STONE_CORE_BROWSER_ST_INTERNAL_H_

#import "stone_core/public/StoneCore.h"

#include <memory>

class Profile;

namespace content {
class WebContents;
}

namespace stone_core {

void SetApplicationDelegate(id<STApplicationDelegate> delegate);
// Routes links macOS asks Stone to open to the delegate instead of Chromium.
void InterceptOpenURLs();
id<STApplicationDelegate> GetApplicationDelegate();

// Called from the browser main parts once Chrome's services are up.
void NotifyApplicationDidStart();
void NotifyApplicationWillShutDown();

STProfile* ProfileFor(Profile* profile);

// Lets extension APIs (scripting, webNavigation, tabs, windows) find Stone's
// tabs and windows, which live outside Chrome's tab strips.
void RegisterTabsWithExtensions();
// tabs.onCreated / onRemoved for Stone tabs.
void AnnounceTabToExtensions(STTab* tab);
void RemoveTabFromExtensions(content::WebContents* contents);
// Stops tab events while profiles shut down.
void SuspendExtensionTabEvents();

STTab* TabForContents(content::WebContents* contents);

// Profiles CHECK on destruction that none of their pages are still alive.
void CloseAllTabs();

}  // namespace stone_core

@interface STApplication ()
- (instancetype)initPrivate NS_DESIGNATED_INITIALIZER;
- (void)startUp;
- (void)shutDown;
- (void)profileWillUnload:(STProfile*)wrapper native:(Profile*)profile;
@end

@interface STProfile ()
@property(readonly) Profile* nativeProfile;
- (instancetype)initWithProfile:(Profile*)profile NS_DESIGNATED_INITIALIZER;
- (void)profileWillBeDestroyed;
- (void)acquireKeepAlive;
@end

namespace download {
class DownloadItem;
}

@interface STDownload ()
- (instancetype)initWithItem:(download::DownloadItem*)item
    NS_DESIGNATED_INITIALIZER;
- (void)itemUpdated;
- (void)itemGone;
@end

@interface STTab ()
@property(readonly) content::WebContents* webContents;
- (instancetype)initWithProfile:(STProfile*)profile
                    webContents:(std::unique_ptr<content::WebContents>)contents
    NS_DESIGNATED_INITIALIZER;
@end

#endif  // STONE_CORE_BROWSER_ST_INTERNAL_H_
