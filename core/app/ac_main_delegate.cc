// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#include "argon_core/app/ac_main_delegate.h"

#include "argon_core/browser/ac_content_browser_client.h"

namespace argon_core {

ACMainDelegate::ACMainDelegate(const StartupTimestamps& timestamps)
    : ChromeMainDelegate(timestamps) {}

ACMainDelegate::~ACMainDelegate() = default;

std::unique_ptr<ChromeContentBrowserClient>
ACMainDelegate::CreateChromeContentBrowserClient() {
  return std::make_unique<ACContentBrowserClient>();
}

}  // namespace argon_core
