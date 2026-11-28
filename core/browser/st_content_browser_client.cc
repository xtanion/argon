// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#include "stone_core/browser/st_content_browser_client.h"

#include "chrome/browser/chrome_browser_main.h"
#include "stone_core/browser/st_browser_main_extra_parts.h"

namespace stone_core {

STContentBrowserClient::STContentBrowserClient() = default;

STContentBrowserClient::~STContentBrowserClient() = default;

std::unique_ptr<content::BrowserMainParts>
STContentBrowserClient::CreateBrowserMainParts(bool is_integration_test) {
  std::unique_ptr<content::BrowserMainParts> parts =
      ChromeContentBrowserClient::CreateBrowserMainParts(is_integration_test);
  static_cast<ChromeBrowserMainParts*>(parts.get())
      ->AddParts(std::make_unique<STBrowserMainExtraParts>());
  return parts;
}

}  // namespace stone_core
