// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#import "argon_core/browser/ac_internal.h"

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

#include <map>
#include <memory>

#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/lifetime/application_lifetime.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/common/pref_names.h"
#include "components/keep_alive_registry/keep_alive_types.h"
#include "components/keep_alive_registry/scoped_keep_alive.h"
#include "components/prefs/pref_service.h"

namespace {

id<ACApplicationDelegate> g_delegate;
ACApplication* g_application;

BOOL HandleReopen(id self, SEL _cmd, NSApplication* app, BOOL hasVisibleWindows) {
  if (g_application &&
      [g_delegate respondsToSelector:@selector(applicationShouldHandleReopen:
                                                            hasVisibleWindows:)]) {
    return [g_delegate applicationShouldHandleReopen:g_application
                                   hasVisibleWindows:hasVisibleWindows];
  }
  return YES;
}

// Chromium's profile picker must never appear: each Space keeps its own
// profile, which Chromium would otherwise treat as a multi-profile user.
void DisableProfilePicker() {
  PrefService* local_state = g_browser_process->local_state();
  constexpr int kAvailabilityDisabled = 1;
  local_state->SetInteger(prefs::kBrowserProfilePickerAvailabilityOnStartup,
                          kAvailabilityDisabled);
  local_state->SetBoolean(prefs::kBrowserShowProfilePickerOnStartup, false);
}

// AppController's reopen handler assumes Chromium owns the windows; with none
// it opens the profile picker or a Chromium browser window.
void InterceptReopen() {
  Class app_controller = NSClassFromString(@"AppController");
  SEL selector = @selector(applicationShouldHandleReopen:hasVisibleWindows:);
  Method method = class_getInstanceMethod(app_controller, selector);
  CHECK(method);
  method_setImplementation(method, reinterpret_cast<IMP>(HandleReopen));
}

}  // namespace

@implementation ACApplication {
  std::unique_ptr<ScopedKeepAlive> _keepAlive;
  std::map<Profile*, ACProfile*> _profiles;
}

+ (ACApplication*)sharedApplication {
  CHECK(g_application);
  return g_application;
}

- (instancetype)initPrivate {
  self = [super init];
  return self;
}

- (void)startUp {
  // Without a Chromium browser window the process would otherwise quit as
  // soon as startup finishes.
  _keepAlive = std::make_unique<ScopedKeepAlive>(
      KeepAliveOrigin::APP_CONTROLLER, KeepAliveRestartOption::DISABLED);
  DisableProfilePicker();
  InterceptReopen();
}

- (void)shutDown {
  for (auto& [profile, wrapper] : _profiles) {
    [wrapper profileWillBeDestroyed];
  }
  _profiles.clear();
  _keepAlive.reset();
}

- (ACProfile*)wrapperForProfile:(Profile*)profile {
  auto it = _profiles.find(profile);
  if (it != _profiles.end()) {
    return it->second;
  }
  ACProfile* wrapper = [[ACProfile alloc] initWithProfile:profile];
  _profiles[profile] = wrapper;
  return wrapper;
}

- (ACProfile*)defaultProfile {
  Profile* profile = ProfileManager::GetLastUsedProfile();
  CHECK(profile);
  return [self wrapperForProfile:profile];
}

- (NSArray<ACProfile*>*)loadedProfiles {
  NSMutableArray<ACProfile*>* result = [NSMutableArray array];
  for (Profile* profile :
       g_browser_process->profile_manager()->GetLoadedProfiles()) {
    [result addObject:[self wrapperForProfile:profile]];
  }
  return result;
}

- (void)loadProfileWithIdentifier:(NSString*)identifier
                       completion:(void (^)(ACProfile*))completion {
  ProfileManager* manager = g_browser_process->profile_manager();
  const base::FilePath path = manager->user_data_dir().Append(
      base::FilePath::FromUTF8Unsafe(base::SysNSStringToUTF8(identifier)));
  __weak ACApplication* weakSelf = self;
  manager->CreateProfileAsync(
      path, base::BindOnce(^(Profile* profile) {
        ACApplication* strongSelf = weakSelf;
        completion(strongSelf && profile
                       ? [strongSelf wrapperForProfile:profile]
                       : nil);
      }));
}

- (void)quit {
  chrome::AttemptExit();
}

@end

namespace argon_core {

void SetApplicationDelegate(id<ACApplicationDelegate> delegate) {
  g_delegate = delegate;
}

id<ACApplicationDelegate> GetApplicationDelegate() {
  return g_delegate;
}

void NotifyApplicationDidStart() {
  g_application = [[ACApplication alloc] initPrivate];
  [g_application startUp];
  [g_delegate applicationDidStart:g_application];
}

void NotifyApplicationWillShutDown() {
  if (!g_application) {
    return;
  }
  if ([g_delegate respondsToSelector:@selector(applicationWillShutDown:)]) {
    [g_delegate applicationWillShutDown:g_application];
  }
  [g_application shutDown];
  g_application = nil;
}

ACProfile* ProfileFor(Profile* profile) {
  return [ACApplication.sharedApplication wrapperForProfile:profile];
}

}  // namespace argon_core
