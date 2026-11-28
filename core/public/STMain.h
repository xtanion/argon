// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef STONE_CORE_PUBLIC_ACMAIN_H_
#define STONE_CORE_PUBLIC_ACMAIN_H_

#import <Foundation/Foundation.h>

#import "STExport.h"

NS_ASSUME_NONNULL_BEGIN

@class STApplication;
@class STProfile;

NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ApplicationDelegate)
@protocol STApplicationDelegate <NSObject>
- (void)applicationDidStart:(STApplication*)application;
@optional
- (void)applicationWillShutDown:(STApplication*)application;
// Dock icon clicked or app relaunched while running. Return YES to let AppKit
// unminimize windows itself.
- (BOOL)applicationShouldHandleReopen:(STApplication*)application
                    hasVisibleWindows:(BOOL)hasVisibleWindows;
// Links opened from other apps while Stone is the default browser, or files
// dropped on the Dock icon. Links that arrive during startup are delivered
// right after applicationDidStart:.
- (void)application:(STApplication*)application openURLs:(NSArray<NSURL*>*)urls;
// Chromium is about to destroy `profile`, after -[STProfile unload] or for its
// own reasons. Drop every reference to it.
- (void)application:(STApplication*)application
    profileWillUnload:(STProfile*)profile;
@end

// Starts Chromium in the browser process and runs the main loop. Returns the
// process exit code. `delegate` is retained for the lifetime of the process.
AC_EXPORT int STMain(int argc,
                     char* _Nullable* _Nonnull argv,
                     id<STApplicationDelegate> delegate);

NS_ASSUME_NONNULL_END

#endif  // STONE_CORE_PUBLIC_ACMAIN_H_
