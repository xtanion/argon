// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef ARGON_CORE_PUBLIC_ACPROFILE_H_
#define ARGON_CORE_PUBLIC_ACPROFILE_H_

#import <Foundation/Foundation.h>

#import "ACExport.h"

NS_ASSUME_NONNULL_BEGIN

@class ACDownload;
@class ACProfile;
@class ACTab;

NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ProfileDownloadDelegate)
@protocol ACProfileDownloadDelegate <NSObject>
@optional
// `isNew` is NO for downloads restored from history.
- (void)profile:(ACProfile*)profile
    didAddDownload:(ACDownload*)download
             isNew:(BOOL)isNew;
- (void)profile:(ACProfile*)profile didUpdateDownload:(ACDownload*)download;
- (void)profile:(ACProfile*)profile didRemoveDownload:(ACDownload*)download;
@end

// A Chromium profile: its own cookies, history, extensions and settings.
AC_OBJC_EXPORT
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(Profile)
@interface ACProfile : NSObject

// Directory name inside the user data directory. Stable across launches.
@property(readonly, copy) NSString* identifier;
@property(readonly, copy) NSString* displayName;
@property(readonly, getter=isOffTheRecord) BOOL offTheRecord;

// The profile's default search engine, as chosen in chrome://settings.
@property(readonly, copy, nullable) NSString* searchEngineName;

// Setting a delegate starts tracking downloads, including ones from history.
@property(weak, nullable) id<ACProfileDownloadDelegate> downloadDelegate;
// Newest first.
@property(readonly, copy) NSArray<ACDownload*>* downloads;

- (ACTab*)createTabWithURL:(nullable NSURL*)url NS_SWIFT_NAME(createTab(url:));
- (nullable NSURL*)searchURLForQuery:(NSString*)query
    NS_SWIFT_NAME(searchURL(for:));

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

#endif  // ARGON_CORE_PUBLIC_ACPROFILE_H_
