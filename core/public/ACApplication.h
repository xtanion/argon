// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef ARGON_CORE_PUBLIC_ACAPPLICATION_H_
#define ARGON_CORE_PUBLIC_ACAPPLICATION_H_

#import <Foundation/Foundation.h>

#import "ACExport.h"

NS_ASSUME_NONNULL_BEGIN

@class ACProfile;

// Process-wide entry point into the engine. Only valid on the main thread,
// after ACApplicationDelegate.applicationDidStart.
AC_OBJC_EXPORT
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(Application)
@interface ACApplication : NSObject

@property(class, readonly) ACApplication* sharedApplication NS_SWIFT_NAME(shared);

// The profile Chromium last used, loaded at startup.
@property(readonly) ACProfile* defaultProfile;

// Profiles currently loaded in this process.
@property(readonly) NSArray<ACProfile*>* loadedProfiles;

// Loads the profile stored in `identifier` (a directory name inside the user
// data directory), creating it on first use.
- (void)loadProfileWithIdentifier:(NSString*)identifier
                       completion:(NS_SWIFT_UI_ACTOR void (^)(ACProfile* _Nullable profile))completion
    NS_SWIFT_NAME(loadProfile(identifier:completion:));

- (void)quit;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

#endif  // ARGON_CORE_PUBLIC_ACAPPLICATION_H_
