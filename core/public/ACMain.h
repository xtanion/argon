// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef ARGON_CORE_PUBLIC_ACMAIN_H_
#define ARGON_CORE_PUBLIC_ACMAIN_H_

#import <Foundation/Foundation.h>

#import "ACExport.h"

NS_ASSUME_NONNULL_BEGIN

@class ACApplication;

NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ApplicationDelegate)
@protocol ACApplicationDelegate <NSObject>
- (void)applicationDidStart:(ACApplication*)application;
@optional
- (void)applicationWillShutDown:(ACApplication*)application;
// Dock icon clicked or app relaunched while running. Return YES to let AppKit
// unminimize windows itself.
- (BOOL)applicationShouldHandleReopen:(ACApplication*)application
                    hasVisibleWindows:(BOOL)hasVisibleWindows;
// Links opened from other apps while Argon is the default browser, or files
// dropped on the Dock icon. Links that arrive during startup are delivered
// right after applicationDidStart:.
- (void)application:(ACApplication*)application openURLs:(NSArray<NSURL*>*)urls;
@end

// Starts Chromium in the browser process and runs the main loop. Returns the
// process exit code. `delegate` is retained for the lifetime of the process.
AC_EXPORT int ACMain(int argc,
                     char* _Nullable* _Nonnull argv,
                     id<ACApplicationDelegate> delegate);

NS_ASSUME_NONNULL_END

#endif  // ARGON_CORE_PUBLIC_ACMAIN_H_
