// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#include "argon_core/browser/ac_browser_main_extra_parts.h"

#include "argon_core/browser/ac_internal.h"

namespace argon_core {

ACBrowserMainExtraParts::ACBrowserMainExtraParts() = default;

ACBrowserMainExtraParts::~ACBrowserMainExtraParts() = default;

void ACBrowserMainExtraParts::PostBrowserStart() {
  NotifyApplicationDidStart();
}

void ACBrowserMainExtraParts::PostMainMessageLoopRun() {
  NotifyApplicationWillShutDown();
}

}  // namespace argon_core
