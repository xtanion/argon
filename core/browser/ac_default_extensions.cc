// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#include "argon_core/browser/ac_default_extensions.h"

#include <array>
#include <string_view>

#include "base/files/file_path.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/path_service.h"
#include "base/strings/strcat.h"
#include "base/task/thread_pool.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/common/chrome_paths.h"
#include "extensions/browser/extension_prefs.h"

namespace argon_core {

namespace {

constexpr auto kDefaultExtensions = std::to_array<std::string_view>({
    // uBlock Origin Lite
    "ddkjiahejlhfcafbddmgiahcphecmpfh",
});

constexpr std::string_view kWebStoreUpdate =
    R"({"external_update_url": "https://clients2.google.com/service/update2/crx"})";

void WriteFiles() {
  base::FilePath dir;
  if (!base::PathService::Get(chrome::DIR_USER_EXTERNAL_EXTENSIONS, &dir) ||
      !base::CreateDirectory(dir)) {
    return;
  }
  for (std::string_view id : kDefaultExtensions) {
    base::FilePath file = dir.AppendASCII(base::StrCat({id, ".json"}));
    if (!base::PathExists(file)) {
      base::WriteFile(file, kWebStoreUpdate);
    }
  }
}

}  // namespace

void WriteDefaultExtensionFiles() {
  base::ThreadPool::PostTask(
      FROM_HERE,
      {base::MayBlock(), base::TaskPriority::USER_BLOCKING,
       base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN},
      base::BindOnce(&WriteFiles));
}

void AcknowledgeDefaultExtensions(Profile* profile) {
  if (!profile || profile->IsOffTheRecord()) {
    return;
  }
  extensions::ExtensionPrefs* prefs = extensions::ExtensionPrefs::Get(profile);
  if (!prefs) {
    return;
  }
  for (std::string_view id : kDefaultExtensions) {
    extensions::ExtensionId extension_id(id);
    if (!prefs->IsExternalExtensionAcknowledged(extension_id)) {
      prefs->AcknowledgeExternalExtension(extension_id);
    }
  }
}

}  // namespace argon_core
