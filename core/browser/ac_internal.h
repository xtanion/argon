// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef ARGON_CORE_BROWSER_AC_INTERNAL_H_
#define ARGON_CORE_BROWSER_AC_INTERNAL_H_

#import "argon_core/public/ArgonCore.h"

#include <memory>

class Profile;

namespace content {
class WebContents;
}

namespace argon_core {

void SetApplicationDelegate(id<ACApplicationDelegate> delegate);
// Routes links macOS asks Argon to open to the delegate instead of Chromium.
void InterceptOpenURLs();
id<ACApplicationDelegate> GetApplicationDelegate();

// Called from the browser main parts once Chrome's services are up.
void NotifyApplicationDidStart();
void NotifyApplicationWillShutDown();

ACProfile* ProfileFor(Profile* profile);

// Profiles CHECK on destruction that none of their pages are still alive.
void CloseAllTabs();

}  // namespace argon_core

@interface ACApplication ()
- (instancetype)initPrivate NS_DESIGNATED_INITIALIZER;
- (void)startUp;
- (void)shutDown;
@end

@interface ACProfile ()
@property(readonly) Profile* nativeProfile;
- (instancetype)initWithProfile:(Profile*)profile NS_DESIGNATED_INITIALIZER;
- (void)profileWillBeDestroyed;
@end

namespace download {
class DownloadItem;
}

@interface ACDownload ()
- (instancetype)initWithItem:(download::DownloadItem*)item
    NS_DESIGNATED_INITIALIZER;
- (void)itemUpdated;
- (void)itemGone;
@end

@interface ACTab ()
@property(readonly) content::WebContents* webContents;
- (instancetype)initWithProfile:(ACProfile*)profile
                    webContents:(std::unique_ptr<content::WebContents>)contents
    NS_DESIGNATED_INITIALIZER;
@end

#endif  // ARGON_CORE_BROWSER_AC_INTERNAL_H_
