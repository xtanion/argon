// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef ARGON_CORE_PUBLIC_ACEXTENSIONTABS_H_
#define ARGON_CORE_PUBLIC_ACEXTENSIONTABS_H_

#import <Foundation/Foundation.h>

#import "ACExport.h"

NS_ASSUME_NONNULL_BEGIN

@class ACProfile;
@class ACTab;

// One window as the extension tabs and windows APIs see it. `key` identifies
// the window across calls and is handed back when an extension opens a tab in
// it.
AC_OBJC_EXPORT
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ExtensionWindow)
@interface ACExtensionWindow : NSObject

@property(readonly) id key;
@property(readonly, copy) NSArray<ACTab*>* tabs;
@property(readonly, nullable) ACTab* activeTab;
@property(readonly, copy) NSArray<ACTab*>* pinnedTabs;
@property(readonly, getter=isFocused) BOOL focused;

- (instancetype)initWithKey:(id)key
                       tabs:(NSArray<ACTab*>*)tabs
                  activeTab:(nullable ACTab*)activeTab
                 pinnedTabs:(NSArray<ACTab*>*)pinnedTabs
                    focused:(BOOL)focused NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ExtensionTabsDelegate)
@protocol ACExtensionTabsDelegate <NSObject>
- (NSArray<ACExtensionWindow*>*)extensionWindowsForProfile:(ACProfile*)profile;
// `windowKey` is nil for the current window. `url` is nil for a new tab page.
- (nullable ACTab*)extensionOpenTabWithURL:(nullable NSURL*)url
                                  inWindow:(nullable id)windowKey
                                   profile:(ACProfile*)profile
                                    active:(BOOL)active
                                    pinned:(BOOL)pinned;
- (void)extensionActivateTab:(ACTab*)tab;
@end

NS_ASSUME_NONNULL_END

#endif  // ARGON_CORE_PUBLIC_ACEXTENSIONTABS_H_
