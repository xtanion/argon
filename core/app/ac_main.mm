// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#import "argon_core/public/ACMain.h"

#include <vector>

#include "base/time/time.h"
#include "chrome/app/chrome_main.h"
#include "argon_core/app/ac_main_delegate.h"
#include "argon_core/browser/ac_internal.h"

int ACMain(int argc, char** argv, id<ACApplicationDelegate> delegate) {
  argon_core::SetApplicationDelegate(delegate);

  argon_core::ACMainDelegate main_delegate(
      {.exe_entry_point_ticks = base::TimeTicks::Now()});

  // Chromium must not open its own browser window; the app owns all windows.
  std::vector<const char*> args(argv, argv + argc);
  args.push_back("--no-startup-window");
  args.push_back("--argon-embedder");
  // Dev builds apply fieldtrial_testing_config, which enables this and adds a menu bar icon.
  args.push_back("--disable-features=OmniboxEverywhere");
  args.push_back(nullptr);

  return ChromeMainWithDelegate(static_cast<int>(args.size() - 1), args.data(),
                                main_delegate);
}
