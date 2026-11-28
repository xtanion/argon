// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef STONE_CORE_APP_ST_MAIN_DELEGATE_H_
#define STONE_CORE_APP_ST_MAIN_DELEGATE_H_

#include <memory>

#include "chrome/app/chrome_main_delegate.h"

namespace stone_core {

// Chrome's main delegate with our browser client, so Chrome's services start
// as usual and we take over only window, tab and dialog creation.
class STMainDelegate : public ChromeMainDelegate {
 public:
  explicit STMainDelegate(const StartupTimestamps& timestamps);
  STMainDelegate(const STMainDelegate&) = delete;
  STMainDelegate& operator=(const STMainDelegate&) = delete;
  ~STMainDelegate() override;

 protected:
  std::unique_ptr<ChromeContentBrowserClient> CreateChromeContentBrowserClient()
      override;
};

}  // namespace stone_core

#endif  // STONE_CORE_APP_ST_MAIN_DELEGATE_H_
