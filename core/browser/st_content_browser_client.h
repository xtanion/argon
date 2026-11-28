// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef STONE_CORE_BROWSER_ST_CONTENT_BROWSER_CLIENT_H_
#define STONE_CORE_BROWSER_ST_CONTENT_BROWSER_CLIENT_H_

#include <memory>

#include "chrome/browser/chrome_content_browser_client.h"

namespace stone_core {

class STContentBrowserClient : public ChromeContentBrowserClient {
 public:
  STContentBrowserClient();
  STContentBrowserClient(const STContentBrowserClient&) = delete;
  STContentBrowserClient& operator=(const STContentBrowserClient&) = delete;
  ~STContentBrowserClient() override;

  // content::ContentBrowserClient:
  std::unique_ptr<content::BrowserMainParts> CreateBrowserMainParts(
      bool is_integration_test) override;
};

}  // namespace stone_core

#endif  // STONE_CORE_BROWSER_ST_CONTENT_BROWSER_CLIENT_H_
