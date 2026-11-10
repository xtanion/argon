// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef ARGON_CORE_PUBLIC_ACTAB_H_
#define ARGON_CORE_PUBLIC_ACTAB_H_

#import <AppKit/AppKit.h>

#import "ACExport.h"

NS_ASSUME_NONNULL_BEGIN

@class ACProfile;
@class ACTab;

typedef NS_ENUM(NSInteger, ACTabOpenDisposition) {
  ACTabOpenDispositionForeground,
  ACTabOpenDispositionBackground,
  ACTabOpenDispositionPopup,
  ACTabOpenDispositionWindow,
} NS_SWIFT_NAME(TabOpenDisposition);

NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(TabDelegate)
@protocol ACTabDelegate <NSObject>
@optional
- (void)tabDidChangeTitle:(ACTab*)tab;
- (void)tabDidChangeURL:(ACTab*)tab;
- (void)tabDidChangeLoading:(ACTab*)tab;
- (void)tabDidChangeNavigationState:(ACTab*)tab;
- (void)tabDidChangeFavicon:(ACTab*)tab;
// The page opened a new tab or window (link with target, window.open,
// middle click). The receiver takes ownership by keeping `newTab`; if it does
// not, the new tab closes.
- (void)tab:(ACTab*)tab
    didRequestNewTab:(ACTab*)newTab
         disposition:(ACTabOpenDisposition)disposition;
// The page asked to close itself (window.close).
- (void)tabDidRequestClose:(ACTab*)tab;
- (void)tab:(ACTab*)tab didRequestFullscreen:(BOOL)fullscreen;
// Find-in-page results for the current search. `activeMatch` is 1-based and 0
// while the count is still being computed.
- (void)tab:(ACTab*)tab
    didUpdateFindMatches:(NSInteger)matches
             activeMatch:(NSInteger)activeMatch;
// Playback, audibility, mute or the media session's title or actions changed.
- (void)tabDidChangeMedia:(ACTab*)tab;
@end

// One web page, backed by a WebContents in `profile`.
AC_OBJC_EXPORT
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(Tab)
@interface ACTab : NSObject

@property(readonly) ACProfile* profile;
@property(weak, nullable) id<ACTabDelegate> delegate;

// The page's view. Add it to any view hierarchy; tabs from different
// profiles can share a window.
@property(readonly) NSView* view;

@property(readonly, copy, nullable) NSURL* url NS_SWIFT_NAME(url);
@property(readonly, copy) NSString* title;
@property(readonly, getter=isLoading) BOOL loading;
@property(readonly) double loadProgress;
@property(readonly) BOOL canGoBack;
@property(readonly) BOOL canGoForward;
@property(readonly, nullable) NSImage* favicon;

// Hidden tabs stop painting and are cheaper to keep around.
@property(getter=isVisible) BOOL visible;

- (void)loadURL:(NSURL*)url NS_SWIFT_NAME(load(_:));
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)stop;
- (void)focus;
- (void)close;
- (void)reloadBypassingCache;

// Opens or closes DevTools docked beside the page inside `view`.
- (void)toggleDevTools;
- (void)showDevToolsConsole;
// Starts DevTools' element picker.
- (void)inspectElement;

- (void)zoomIn;
- (void)zoomOut;
- (void)resetZoom;
// The page zoom as a percentage; 100 is the default size.
@property(readonly) NSInteger zoomPercent;

// A snapshot of the visible page at full resolution, delivered on the main
// thread. nil when the page has nothing to copy yet.
- (void)captureVisibleContentWithCompletion:
    (void (^)(NSImage* _Nullable image))completion
    NS_SWIFT_NAME(captureVisibleContent(completion:));

// The page's media session: set while it has controllable media, playing or
// paused.
@property(readonly) BOOL hasMedia;
@property(readonly, getter=isPlayingMedia) BOOL playingMedia;
@property(readonly, getter=isAudible) BOOL audible;
@property(getter=isMuted) BOOL muted;
// The media session's title, or empty when the page sets none.
@property(readonly, copy) NSString* mediaTitle;
@property(readonly) BOOL canPlayPreviousTrack;
@property(readonly) BOOL canPlayNextTrack;
@property(readonly) BOOL canEnterPictureInPicture;
@property(readonly, getter=isInPictureInPicture) BOOL inPictureInPicture;
- (void)playMedia;
- (void)pauseMedia;
- (void)previousTrack;
- (void)nextTrack;
- (void)togglePictureInPicture;
// Whether this site may go into picture in picture when you leave its tab.
// Stored as Chrome's per-site auto picture-in-picture setting; only an explicit
// block turns it off. Always NO for pages that are not http or https.
@property(nonatomic) BOOL autoPictureInPictureAllowed;
- (void)stopMedia;

// Chrome's print preview, shown over the page.
- (void)print;
- (void)printUsingSystemDialog;
// Save Page As, with the save panel.
- (void)savePage;

// Searches the page. Repeating the same text moves to the next or previous
// match. Results arrive through the delegate.
- (void)findText:(NSString*)text
         forward:(BOOL)forward
   caseSensitive:(BOOL)caseSensitive
    NS_SWIFT_NAME(find(_:forward:caseSensitive:));
// Ends the search. Keeps the active match selected unless `clearSelection`.
- (void)stopFindingClearingSelection:(BOOL)clearSelection
    NS_SWIFT_NAME(stopFinding(clearSelection:));
// The last text searched in this tab.
@property(readonly, copy) NSString* findText;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

#endif  // ARGON_CORE_PUBLIC_ACTAB_H_
