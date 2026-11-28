// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef STONE_CORE_PUBLIC_ACIMPORT_H_
#define STONE_CORE_PUBLIC_ACIMPORT_H_

#import <Foundation/Foundation.h>

#import "STExport.h"
#import "STProfile.h"

NS_ASSUME_NONNULL_BEGIN

// A history entry read from another browser.
AC_OBJC_EXPORT
NS_SWIFT_NAME(ImportedVisit)
@interface STImportedVisit : NSObject
@property(copy) NSURL* url;
@property(copy) NSString* title;
@property NSInteger visitCount;
@property NSInteger typedCount;
@property(copy) NSDate* lastVisit;
@end

// A saved login read from another browser, already decrypted.
AC_OBJC_EXPORT
NS_SWIFT_NAME(ImportedLogin)
@interface STImportedLogin : NSObject
@property(copy) NSURL* url;
@property(copy, nullable) NSURL* actionURL;
@property(copy) NSString* signonRealm;
@property(copy) NSString* usernameElement;
@property(copy) NSString* username;
@property(copy) NSString* passwordElement;
@property(copy) NSString* password;
@property(copy, nullable) NSDate* dateCreated;
@property(copy, nullable) NSDate* dateLastUsed;
@property NSInteger timesUsed;
@end

// A cookie read from another browser, already decrypted. Enum values use
// Chromium's cookie database encoding.
AC_OBJC_EXPORT
NS_SWIFT_NAME(ImportedCookie)
@interface STImportedCookie : NSObject
@property(copy) NSString* name;
@property(copy) NSString* value;
@property(copy) NSString* domain;
@property(copy) NSString* path;
@property(copy) NSDate* creation;
@property(copy, nullable) NSDate* expiration;
@property(copy) NSDate* lastAccess;
@property(copy) NSDate* lastUpdate;
@property BOOL secure;
@property BOOL httpOnly;
@property NSInteger sameSite;
@property NSInteger priority;
@property NSInteger sourceScheme;
@property NSInteger sourcePort;
@property NSInteger sourceType;
@end

@interface STProfile (Import)

- (void)importHistory:(NSArray<STImportedVisit*>*)visits
    NS_SWIFT_NAME(importHistory(_:));

- (void)importLogins:(NSArray<STImportedLogin*>*)logins
          completion:(NS_SWIFT_UI_ACTOR void (^)(void))completion
    NS_SWIFT_NAME(importLogins(_:completion:));

// `imported` counts the cookies the cookie store accepted.
- (void)importCookies:(NSArray<STImportedCookie*>*)cookies
           completion:(NS_SWIFT_UI_ACTOR void (^)(NSInteger imported))completion
    NS_SWIFT_NAME(importCookies(_:completion:));

@end

NS_ASSUME_NONNULL_END

#endif  // STONE_CORE_PUBLIC_ACIMPORT_H_
