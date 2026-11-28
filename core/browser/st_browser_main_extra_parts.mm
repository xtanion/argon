// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#include "stone_core/browser/st_browser_main_extra_parts.h"

#include "stone_core/browser/st_default_extensions.h"
#include "stone_core/browser/st_internal.h"

namespace stone_core {

STBrowserMainExtraParts::STBrowserMainExtraParts() = default;

STBrowserMainExtraParts::~STBrowserMainExtraParts() = default;

void STBrowserMainExtraParts::PreProfileInit() {
  WriteDefaultExtensionFiles();
}

void STBrowserMainExtraParts::PostProfileInit(Profile* profile,
                                              bool is_initial_profile) {
  AcknowledgeDefaultExtensions(profile);
}

void STBrowserMainExtraParts::PostBrowserStart() {
  NotifyApplicationDidStart();
}

void STBrowserMainExtraParts::PostMainMessageLoopRun() {
  NotifyApplicationWillShutDown();
}

}  // namespace stone_core
