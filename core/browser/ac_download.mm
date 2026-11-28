// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#import "argon_core/browser/ac_internal.h"

#import <AppKit/AppKit.h>

#include "base/apple/foundation_util.h"
#include "base/files/file_path.h"
#include "base/files/file_path.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/time/time.h"
#include "components/download/public/common/download_item.h"
#include "net/base/apple/url_conversions.h"

namespace {

ACDownloadState ToState(download::DownloadItem::DownloadState state) {
  switch (state) {
    case download::DownloadItem::COMPLETE:
      return ACDownloadStateComplete;
    case download::DownloadItem::CANCELLED:
      return ACDownloadStateCancelled;
    case download::DownloadItem::INTERRUPTED:
      return ACDownloadStateInterrupted;
    default:
      return ACDownloadStateInProgress;
  }
}

NSURL* FileURL(const base::FilePath& path) {
  return path.empty() ? nil : base::apple::FilePathToNSURL(path);
}

}  // namespace

@implementation ACDownload {
  raw_ptr<download::DownloadItem> _item;
  NSString* _identifier;
  NSString* _fileName;
  NSURL* _fileURL;
  NSURL* _sourceURL;
  ACDownloadState _state;
  BOOL _paused;
  BOOL _canResume;
  int64_t _receivedBytes;
  int64_t _totalBytes;
  int64_t _bytesPerSecond;
  NSDate* _startDate;
  NSDate* _endDate;
}

- (instancetype)initWithItem:(download::DownloadItem*)item {
  self = [super init];
  if (self) {
    _item = item;
    _identifier = base::SysUTF8ToNSString(item->GetGuid());
    [self snapshot];
  }
  return self;
}

- (void)snapshot {
  if (!_item) {
    return;
  }
  _fileName =
      base::SysUTF8ToNSString(_item->GetFileNameToReportUser().AsUTF8Unsafe());
  const base::FilePath& target = _item->GetTargetFilePath();
  _fileURL = FileURL(target.empty() ? _item->GetFullPath() : target);
  const GURL& url = _item->GetURL();
  _sourceURL = url.is_valid() ? net::NSURLWithGURL(url) : nil;
  _state = ToState(_item->GetState());
  _paused = _item->IsPaused();
  _canResume = _item->CanResume();
  _receivedBytes = _item->GetReceivedBytes();
  _totalBytes = _item->GetTotalBytes() > 0 ? _item->GetTotalBytes() : -1;
  _bytesPerSecond = _item->CurrentSpeed();
  _startDate = _item->GetStartTime().ToNSDate();
  base::Time end = _item->GetEndTime();
  _endDate = end.is_null() ? nil : end.ToNSDate();
}

- (void)itemUpdated {
  [self snapshot];
}

- (void)itemGone {
  [self snapshot];
  _item = nullptr;
}

- (NSString*)identifier {
  return _identifier;
}

- (NSString*)fileName {
  return _fileName ?: @"";
}

- (NSURL*)fileURL {
  return _fileURL;
}

- (NSURL*)sourceURL {
  return _sourceURL;
}

- (ACDownloadState)state {
  return _state;
}

- (BOOL)isPaused {
  return _paused;
}

- (BOOL)canResume {
  return _canResume;
}

- (BOOL)fileExists {
  if (_item && _item->GetFileExternallyRemoved()) {
    return NO;
  }
  return _fileURL && [NSFileManager.defaultManager
                         fileExistsAtPath:_fileURL.path];
}

- (int64_t)receivedBytes {
  return _receivedBytes;
}

- (int64_t)totalBytes {
  return _totalBytes;
}

- (int64_t)bytesPerSecond {
  return _bytesPerSecond;
}

- (NSDate*)startDate {
  return _startDate ?: [NSDate date];
}

- (NSDate*)endDate {
  return _endDate;
}

- (void)open {
  if (_item) {
    _item->OpenDownload();
  }
}

- (void)showInFinder {
  if (_item) {
    _item->ShowDownloadInShell();
  } else if (_fileURL) {
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[ _fileURL ]];
  }
}

- (void)pause {
  if (_item) {
    _item->Pause();
  }
}

- (void)resume {
  if (_item && _item->CanResume()) {
    _item->Resume(true);
  }
}

- (void)cancel {
  if (_item) {
    _item->Cancel(true);
  }
}

- (void)remove {
  if (_item) {
    _item->Remove();
  }
}

@end
