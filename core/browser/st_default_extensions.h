// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef STONE_CORE_BROWSER_ST_DEFAULT_EXTENSIONS_H_
#define STONE_CORE_BROWSER_ST_DEFAULT_EXTENSIONS_H_

class Profile;

namespace stone_core {

// Lists Stone's default extensions in the user External Extensions directory,
// so every profile installs them from the Chrome Web Store. Removing one
// records an external uninstall and it does not come back.
void WriteDefaultExtensionFiles();

// Chrome installs external extensions disabled until the user approves them
// in a menu bubble Stone does not have. Default extensions are approved
// up front.
void AcknowledgeDefaultExtensions(Profile* profile);

}  // namespace stone_core

#endif  // STONE_CORE_BROWSER_ST_DEFAULT_EXTENSIONS_H_
