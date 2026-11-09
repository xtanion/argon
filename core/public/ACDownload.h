// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef ARGON_CORE_PUBLIC_ACDOWNLOAD_H_
#define ARGON_CORE_PUBLIC_ACDOWNLOAD_H_

#import <Foundation/Foundation.h>

#import "ACExport.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ACDownloadState) {
  ACDownloadStateInProgress,
  ACDownloadStateComplete,
  ACDownloadStateCancelled,
  ACDownloadStateInterrupted,
} NS_SWIFT_NAME(DownloadState);

// One download in a profile. Properties read the live download; once it is
// removed or destroyed they keep their last values.
AC_OBJC_EXPORT
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(Download)
@interface ACDownload : NSObject

@property(readonly, copy) NSString* identifier;
@property(readonly, copy) NSString* fileName;
@property(readonly, copy, nullable) NSURL* fileURL;
@property(readonly, copy, nullable) NSURL* sourceURL;
@property(readonly) ACDownloadState state;
@property(readonly, getter=isPaused) BOOL paused;
@property(readonly) BOOL canResume;
@property(readonly) BOOL fileExists;
@property(readonly) int64_t receivedBytes;
// -1 when the size is unknown.
@property(readonly) int64_t totalBytes;
@property(readonly) int64_t bytesPerSecond;
@property(readonly, copy) NSDate* startDate;
@property(readonly, copy, nullable) NSDate* endDate;

- (void)open;
- (void)showInFinder;
- (void)pause;
- (void)resume;
- (void)cancel;
// Removes the download from the list; the file stays on disk.
- (void)remove;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

#endif  // ARGON_CORE_PUBLIC_ACDOWNLOAD_H_
