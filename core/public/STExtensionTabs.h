// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef STONE_CORE_PUBLIC_ACEXTENSIONTABS_H_
#define STONE_CORE_PUBLIC_ACEXTENSIONTABS_H_

#import <AppKit/AppKit.h>

#import "STExport.h"

NS_ASSUME_NONNULL_BEGIN

@class STApplication;
@class STProfile;
@class STTab;

// One window as the extension tabs and windows APIs see it. `key` identifies
// the window across calls and is handed back when an extension opens a tab in
// it.
AC_OBJC_EXPORT
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ExtensionWindow)
@interface STExtensionWindow : NSObject

@property(readonly) id key;
@property(readonly, copy) NSArray<STTab*>* tabs;
@property(readonly, nullable) STTab* activeTab;
@property(readonly, copy) NSArray<STTab*>* pinnedTabs;
@property(readonly, getter=isFocused) BOOL focused;
@property(readonly, weak, nullable) NSWindow* window;

- (instancetype)initWithKey:(id)key
                       tabs:(NSArray<STTab*>*)tabs
                  activeTab:(nullable STTab*)activeTab
                 pinnedTabs:(NSArray<STTab*>*)pinnedTabs
                    focused:(BOOL)focused
                     window:(nullable NSWindow*)window NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ExtensionTabsDelegate)
@protocol STExtensionTabsDelegate <NSObject>
- (NSArray<STExtensionWindow*>*)extensionWindowsForProfile:(STProfile*)profile;
// `windowKey` is nil for the current window. `url` is nil for a new tab page.
- (nullable STTab*)extensionOpenTabWithURL:(nullable NSURL*)url
                                  inWindow:(nullable id)windowKey
                                   profile:(STProfile*)profile
                                    active:(BOOL)active
                                    pinned:(BOOL)pinned;
- (void)extensionActivateTab:(STTab*)tab;
@end

@interface STApplication (ExtensionTabs)
// Call when spaces are added or removed, so chrome.windows sees them.
- (void)extensionWindowsDidChange;
// Call when the user switches to `tab`, for chrome.tabs.onActivated.
- (void)extensionTabDidActivate:(STTab*)tab;
@end

NS_ASSUME_NONNULL_END

#endif  // STONE_CORE_PUBLIC_ACEXTENSIONTABS_H_
