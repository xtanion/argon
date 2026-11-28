// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#import "stone_core/public/STMain.h"

#include <string>
#include <vector>

#include "base/time/time.h"
#include "chrome/app/chrome_main.h"
#include "stone_core/app/st_main_delegate.h"
#include "stone_core/browser/st_internal.h"

namespace {

// Stone ships no AI features: no Gemini, no on-device model download, and no
// built-in AI web APIs for pages.
constexpr const char* kDisabledAIFeatures[] = {
    "Glic",
    "ApiGlicPrivate",
    "ApiContextualTasksPrivate",
    "PreemptiveSodaDownload",
    "GlicRollout",
    "GlicActor",
    "GlicTieredRollout",
    "GlicTieredRolloutV2",
    "GlicWarming",
    "GlicWebContentsWarming",
    "GlicContextMenu",
    "GlicTextSelectionContextMenu",
    "GlicExtensions",
    "PasswordChangeWithGlic",
    "Compose",
    "ComposeEligible",
    "ComposeGraduated",
    "NtpComposebox",
    "AimEnabled",
    "AimServerEligibilityEnabled",
    "AimServerRequestOnStartupEnabled",
    "AiOverlayDialog",
    "LensOverlay",
    "LensOverlayContextualSearchbox",
    "LensOverlayTextSelectionContextMenuEntrypoint",
    "LensOverlayImageContextMenuActions",
    "LensAimSuggestions",
    "ContextualCueing",
    "ContextualCueingV2",
    "ContextualTasks",
    "ContextualTasksContextMenu",
    "SkillsEnabled",
    "HistoryEmbeddings",
    "HistoryEmbeddingsAnswers",
    "PassageEmbedder",
    "CustomizeChromeWallpaperSearch",
    "OrganizerPanel",
    "AutofillAiShipment",
    "AutofillAiUsePrivateAi",
    "PermissionsAIv4",
    "PermissionsAIP92",
    "OptimizationGuideModelExecution",
    "OnDeviceModelBackgroundDownload",
    "OnDeviceWebSpeechGeminiNano",
    "AIApiFoundationalModel",
    "AIPromptAPI",
    "AISummarizationAPI",
    "AIWriterAPI",
    "AIRewriterAPI",
    "AIProofreadingAPI",
    "DevToolsConsoleInsights",
    "DevToolsFreestyler",
    "DevToolsAiCodeCompletion",
    "DevToolsAiCodeGeneration",
    "DevToolsAiGeneratedTimelineLabels",
    "DevToolsGlobalAiButton",
};

constexpr char kDisabledAIWebAPIs[] =
    "AIPromptAPI,AIPromptAPIForWorkers,AISummarizationAPI,"
    "AISummarizationAPIForWorkers,AIWriterAPI,AIWriterAPIForWorkers,"
    "AIRewriterAPI,AIRewriterAPIForWorkers,AIProofreaderAPI,"
    "AIProofreadingAPI,AIEmbeddingsAPI,AIDecisionModelAPI";

}  // namespace

int STMain(int argc, char** argv, id<STApplicationDelegate> delegate) {
  stone_core::SetApplicationDelegate(delegate);
  stone_core::InterceptOpenURLs();

  stone_core::STMainDelegate main_delegate(
      {.exe_entry_point_ticks = base::TimeTicks::Now()});

  // Chromium must not open its own browser window; the app owns all windows.
  std::vector<const char*> args(argv, argv + argc);
  args.push_back("--no-startup-window");
  args.push_back("--stone-embedder");
  // Chromium builds, release included, apply fieldtrial_testing_config: about a
  // thousand experiments, among them Gemini, Contextual Tasks, dictation, an
  // unprompted Live Caption download and OmniboxEverywhere's menu bar icon.
  args.push_back("--disable-field-trial-config");
  std::string disabled = "OmniboxEverywhere";
  for (const char* feature : kDisabledAIFeatures) {
    disabled.append(",").append(feature);
  }
  disabled = "--disable-features=" + disabled;
  std::string blink_disabled =
      std::string("--disable-blink-features=") + kDisabledAIWebAPIs;
  args.push_back(disabled.c_str());
  // Tab sleep discards pages in place; off by default outside Android.
  // Without a Browser window the old startup tracking can wait for its three
  // minute failsafe, holding back BEST_EFFORT work such as extension installs.
  args.push_back(
      "--enable-features=WebContentsDiscard,ImprovedStartupBestEffortDelay");
  args.push_back(blink_disabled.c_str());
  args.push_back(nullptr);

  return ChromeMainWithDelegate(static_cast<int>(args.size() - 1), args.data(),
                                main_delegate);
}
