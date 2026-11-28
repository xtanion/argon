// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef ARGON_CORE_APP_AC_MAIN_DELEGATE_H_
#define ARGON_CORE_APP_AC_MAIN_DELEGATE_H_

#include <memory>

#include "chrome/app/chrome_main_delegate.h"

namespace argon_core {

// Chrome's main delegate with our browser client, so Chrome's services start
// as usual and we take over only window, tab and dialog creation.
class ACMainDelegate : public ChromeMainDelegate {
 public:
  explicit ACMainDelegate(const StartupTimestamps& timestamps);
  ACMainDelegate(const ACMainDelegate&) = delete;
  ACMainDelegate& operator=(const ACMainDelegate&) = delete;
  ~ACMainDelegate() override;

 protected:
  std::unique_ptr<ChromeContentBrowserClient> CreateChromeContentBrowserClient()
      override;
};

}  // namespace argon_core

#endif  // ARGON_CORE_APP_AC_MAIN_DELEGATE_H_
