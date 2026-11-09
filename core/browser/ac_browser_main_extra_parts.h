// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef ARGON_CORE_BROWSER_AC_BROWSER_MAIN_EXTRA_PARTS_H_
#define ARGON_CORE_BROWSER_AC_BROWSER_MAIN_EXTRA_PARTS_H_

#include "chrome/browser/chrome_browser_main_extra_parts.h"

namespace argon_core {

class ACBrowserMainExtraParts : public ChromeBrowserMainExtraParts {
 public:
  ACBrowserMainExtraParts();
  ACBrowserMainExtraParts(const ACBrowserMainExtraParts&) = delete;
  ACBrowserMainExtraParts& operator=(const ACBrowserMainExtraParts&) = delete;
  ~ACBrowserMainExtraParts() override;

  // ChromeBrowserMainExtraParts:
  void PostBrowserStart() override;
  void PostMainMessageLoopRun() override;
};

}  // namespace argon_core

#endif  // ARGON_CORE_BROWSER_AC_BROWSER_MAIN_EXTRA_PARTS_H_
