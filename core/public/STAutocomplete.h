// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef STONE_CORE_PUBLIC_ACAUTOCOMPLETE_H_
#define STONE_CORE_PUBLIC_ACAUTOCOMPLETE_H_

#import <AppKit/AppKit.h>

#import "STExport.h"

NS_ASSUME_NONNULL_BEGIN

@class STProfile;

typedef NS_ENUM(NSInteger, STAutocompleteMatchKind) {
  STAutocompleteMatchKindURL,
  STAutocompleteMatchKindHistory,
  STAutocompleteMatchKindBookmark,
  STAutocompleteMatchKindSearch,
  STAutocompleteMatchKindSearchHistory,
  STAutocompleteMatchKindOther,
} NS_SWIFT_NAME(AutocompleteMatchKind);

// One row of Chrome's omnibox results.
AC_OBJC_EXPORT
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(AutocompleteMatch)
@interface STAutocompleteMatch : NSObject

@property(readonly) STAutocompleteMatchKind kind;
@property(readonly, copy) NSString* contents;
@property(readonly, copy) NSString* matchDescription;
@property(readonly, copy) NSString* fillIntoEdit;
@property(readonly, copy, nullable) NSURL* destinationURL;
// Text to append after what the user typed when this is the default match.
@property(readonly, copy) NSString* inlineAutocompletion;
@property(readonly) BOOL allowedToBeDefault;
@property(readonly) int relevance;

- (instancetype)init NS_UNAVAILABLE;

@end

// Runs Chrome's autocomplete (history, shortcuts, bookmarks, search
// suggestions) for one profile.
AC_OBJC_EXPORT
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(Autocomplete)
@interface STAutocomplete : NSObject

- (instancetype)initWithProfile:(STProfile*)profile;
- (instancetype)init NS_UNAVAILABLE;

// Called every time the result set changes, possibly several times per query.
@property(copy, nullable) void (^onResultsChanged)
    (NSArray<STAutocompleteMatch*>* matches);
@property(readonly, copy) NSArray<STAutocompleteMatch*>* matches;

- (void)startWithText:(NSString*)text
    preventInlineAutocomplete:(BOOL)preventInline
    NS_SWIFT_NAME(start(text:preventInlineAutocomplete:));
- (void)stop;

// Records that the user opened `match` for the last query so shortcuts learn.
- (void)didOpenMatch:(STAutocompleteMatch*)match
    NS_SWIFT_NAME(didOpen(_:));

- (void)faviconForURL:(NSURL*)url
           completion:(void (^)(NSImage* _Nullable image))completion
    NS_SWIFT_NAME(favicon(for:completion:));

@end

NS_ASSUME_NONNULL_END

#endif  // STONE_CORE_PUBLIC_ACAUTOCOMPLETE_H_
