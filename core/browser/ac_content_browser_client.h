// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef ARGON_CORE_BROWSER_AC_CONTENT_BROWSER_CLIENT_H_
#define ARGON_CORE_BROWSER_AC_CONTENT_BROWSER_CLIENT_H_

#include <memory>

#include "chrome/browser/chrome_content_browser_client.h"

namespace argon_core {

class ACContentBrowserClient : public ChromeContentBrowserClient {
 public:
  ACContentBrowserClient();
  ACContentBrowserClient(const ACContentBrowserClient&) = delete;
  ACContentBrowserClient& operator=(const ACContentBrowserClient&) = delete;
  ~ACContentBrowserClient() override;

  // content::ContentBrowserClient:
  std::unique_ptr<content::BrowserMainParts> CreateBrowserMainParts(
      bool is_integration_test) override;
};

}  // namespace argon_core

#endif  // ARGON_CORE_BROWSER_AC_CONTENT_BROWSER_CLIENT_H_
