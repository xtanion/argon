// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef ARGON_CORE_BROWSER_AC_DEFAULT_EXTENSIONS_H_
#define ARGON_CORE_BROWSER_AC_DEFAULT_EXTENSIONS_H_

class Profile;

namespace argon_core {

// Lists Argon's default extensions in the user External Extensions directory,
// so every profile installs them from the Chrome Web Store. Removing one
// records an external uninstall and it does not come back.
void WriteDefaultExtensionFiles();

// Chrome installs external extensions disabled until the user approves them
// in a menu bubble Argon does not have. Default extensions are approved
// up front.
void AcknowledgeDefaultExtensions(Profile* profile);

}  // namespace argon_core

#endif  // ARGON_CORE_BROWSER_AC_DEFAULT_EXTENSIONS_H_
