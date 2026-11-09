// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#include "argon_core/browser/ac_content_browser_client.h"

#include "chrome/browser/chrome_browser_main.h"
#include "argon_core/browser/ac_browser_main_extra_parts.h"

namespace argon_core {

ACContentBrowserClient::ACContentBrowserClient() = default;

ACContentBrowserClient::~ACContentBrowserClient() = default;

std::unique_ptr<content::BrowserMainParts>
ACContentBrowserClient::CreateBrowserMainParts(bool is_integration_test) {
  std::unique_ptr<content::BrowserMainParts> parts =
      ChromeContentBrowserClient::CreateBrowserMainParts(is_integration_test);
  static_cast<ChromeBrowserMainParts*>(parts.get())
      ->AddParts(std::make_unique<ACBrowserMainExtraParts>());
  return parts;
}

}  // namespace argon_core
