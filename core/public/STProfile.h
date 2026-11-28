// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef STONE_CORE_PUBLIC_ACPROFILE_H_
#define STONE_CORE_PUBLIC_ACPROFILE_H_

#import <Foundation/Foundation.h>

#import "STExport.h"

NS_ASSUME_NONNULL_BEGIN

@class STDownload;
@class STProfile;
@class STTab;

NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ProfileDownloadDelegate)
@protocol STProfileDownloadDelegate <NSObject>
@optional
// `isNew` is NO for downloads restored from history.
- (void)profile:(STProfile*)profile
    didAddDownload:(STDownload*)download
             isNew:(BOOL)isNew;
- (void)profile:(STProfile*)profile didUpdateDownload:(STDownload*)download;
- (void)profile:(STProfile*)profile didRemoveDownload:(STDownload*)download;
@end

// A Chromium profile: its own cookies, history, extensions and settings.
AC_OBJC_EXPORT
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(Profile)
@interface STProfile : NSObject

// Directory name inside the user data directory. Stable across launches.
@property(readonly, copy) NSString* identifier;
@property(readonly, copy) NSString* displayName;
@property(readonly, getter=isOffTheRecord) BOOL offTheRecord;

// The profile's default search engine, as chosen in chrome://settings.
@property(readonly, copy, nullable) NSString* searchEngineName;

// Setting a delegate starts tracking downloads, including ones from history.
@property(weak, nullable) id<STProfileDownloadDelegate> downloadDelegate;
// Newest first.
@property(readonly, copy) NSArray<STDownload*>* downloads;

- (STTab*)createTabWithURL:(nullable NSURL*)url NS_SWIFT_NAME(createTab(url:));
- (nullable NSURL*)searchURLForQuery:(NSString*)query
    NS_SWIFT_NAME(searchURL(for:));

// Starts DNS, TCP and TLS setup for `url`'s server ahead of a likely
// navigation, the way Chrome's address bar does for its top suggestion.
- (void)preconnectToURL:(NSURL*)url NS_SWIFT_NAME(preconnect(to:));

// Lets Chromium unload the profile once nothing else keeps it alive. Drop every
// reference to the receiver afterwards and load the profile again by
// identifier when it is next needed.
- (void)unload;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

#endif  // STONE_CORE_PUBLIC_ACPROFILE_H_
