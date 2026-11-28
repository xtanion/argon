// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef STONE_CORE_BROWSER_ST_BROWSER_MAIN_EXTRA_PARTS_H_
#define STONE_CORE_BROWSER_ST_BROWSER_MAIN_EXTRA_PARTS_H_

#include "chrome/browser/chrome_browser_main_extra_parts.h"

namespace stone_core {

class STBrowserMainExtraParts : public ChromeBrowserMainExtraParts {
 public:
  STBrowserMainExtraParts();
  STBrowserMainExtraParts(const STBrowserMainExtraParts&) = delete;
  STBrowserMainExtraParts& operator=(const STBrowserMainExtraParts&) = delete;
  ~STBrowserMainExtraParts() override;

  // ChromeBrowserMainExtraParts:
  void PreProfileInit() override;
  void PostProfileInit(Profile* profile, bool is_initial_profile) override;
  void PostBrowserStart() override;
  void PostMainMessageLoopRun() override;
};

}  // namespace stone_core

#endif  // STONE_CORE_BROWSER_ST_BROWSER_MAIN_EXTRA_PARTS_H_
