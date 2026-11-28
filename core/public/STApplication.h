// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef STONE_CORE_PUBLIC_ACAPPLICATION_H_
#define STONE_CORE_PUBLIC_ACAPPLICATION_H_

#import <Foundation/Foundation.h>

#import "STExport.h"

NS_ASSUME_NONNULL_BEGIN

@class STProfile;
@protocol STExtensionTabsDelegate;

// Process-wide entry point into the engine. Only valid on the main thread,
// after STApplicationDelegate.applicationDidStart.
AC_OBJC_EXPORT
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(Application)
@interface STApplication : NSObject

@property(class, readonly) STApplication* sharedApplication NS_SWIFT_NAME(shared);

// The profile Chromium last used, loaded at startup.
@property(readonly) STProfile* defaultProfile;

// Profiles currently loaded in this process.
@property(readonly) NSArray<STProfile*>* loadedProfiles;

// Supplies the windows and tabs extensions see through chrome.tabs.
@property(weak, nullable) id<STExtensionTabsDelegate> extensionTabsDelegate;

// Loads the profile stored in `identifier` (a directory name inside the user
// data directory), creating it on first use.
- (void)loadProfileWithIdentifier:(NSString*)identifier
                       completion:(NS_SWIFT_UI_ACTOR void (^)(STProfile* _Nullable profile))completion
    NS_SWIFT_NAME(loadProfile(identifier:completion:));

- (void)quit;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

#endif  // STONE_CORE_PUBLIC_ACAPPLICATION_H_
