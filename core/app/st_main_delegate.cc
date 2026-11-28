// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#include "stone_core/app/st_main_delegate.h"

#include "stone_core/browser/st_content_browser_client.h"

namespace stone_core {

STMainDelegate::STMainDelegate(const StartupTimestamps& timestamps)
    : ChromeMainDelegate(timestamps) {}

STMainDelegate::~STMainDelegate() = default;

std::unique_ptr<ChromeContentBrowserClient>
STMainDelegate::CreateChromeContentBrowserClient() {
  return std::make_unique<STContentBrowserClient>();
}

}  // namespace stone_core
