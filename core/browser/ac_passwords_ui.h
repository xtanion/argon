// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef ARGON_CORE_BROWSER_AC_PASSWORDS_UI_H_
#define ARGON_CORE_BROWSER_AC_PASSWORDS_UI_H_

#include <memory>
#include <string>
#include <vector>

#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/passwords/passwords_client_ui_delegate.h"
#include "components/password_manager/core/browser/password_form_manager_for_ui.h"
#include "content/public/browser/web_contents_user_data.h"

@class NSAlert;

namespace argon_core {

// Stands in for Chrome's ManagePasswordsUIController on Argon tabs, which have
// no location bar to anchor its bubbles. Save and update offers become a sheet
// on the tab's window; everything else is dropped.
class ACPasswordsUI : public PasswordsClientUIDelegate,
                      public content::WebContentsUserData<ACPasswordsUI> {
 public:
  ~ACPasswordsUI() override;

  static void Install();

  void OnPasswordSubmitted(
      std::unique_ptr<password_manager::PasswordFormManagerForUI> form_manager)
      override;
  void OnUpdatePasswordSubmitted(
      std::unique_ptr<password_manager::PasswordFormManagerForUI> form_manager)
      override;
  void OnShowManualFallbackForSaving(
      std::unique_ptr<password_manager::PasswordFormManagerForUI> form_manager,
      bool has_generated_password,
      bool is_update) override {}
  void OnHideManualFallbackForSaving() override {}
  void OnOpenPasswordDetailsBubble(
      const password_manager::PasswordForm& form) override {}
  bool OnChooseCredentials(
      std::vector<std::unique_ptr<password_manager::PasswordForm>>
          local_credentials,
      const url::Origin& origin,
      base::OnceCallback<void(const password_manager::PasswordForm*)> callback)
      override;
  void OnAutoSignin(
      std::vector<std::unique_ptr<password_manager::PasswordForm>> local_forms,
      const url::Origin& origin) override {}
  void OnPromptEnableAutoSignin() override {}
  void OnAutomaticPasswordSave(
      std::unique_ptr<password_manager::PasswordFormManagerForUI> form_manager,
      bool is_update_confirmation) override {}
  void OnPasswordAutofilled(
      base::span<const password_manager::StoredCredential> password_credentials,
      const url::Origin& origin,
      base::span<const password_manager::StoredCredential> federated_matches)
      override {}
  void OnCredentialLeak(
      password_manager::LeakedPasswordDetails details) override {}
  void OnShowMoveToAccountBubble(
      std::unique_ptr<password_manager::PasswordFormManagerForUI> form_to_move)
      override {}
  void OnBiometricAuthenticationForFilling(PrefService* pref_service) override {
  }
  void OnKeychainError() override {}
  void OnPasskeySaved(bool gpm_pin_created,
                      std::string passkey_rp_id) override {}
  void OnPasskeyDeleted() override {}
  void OnPasskeyUpdated(std::string passkey_rp_id) override {}
  void OnPasskeyNotAccepted(std::string passkey_rp_id) override {}
  void OnPasskeyUpgrade(std::string passkey_rp_id) override {}

 private:
  explicit ACPasswordsUI(content::WebContents* web_contents);
  friend WebContentsUserData;

  void Offer(
      std::unique_ptr<password_manager::PasswordFormManagerForUI> form_manager,
      bool update);
  void OnResponse(long response);
  void Dismiss();

  std::unique_ptr<password_manager::PasswordFormManagerForUI> pending_;
  bool pending_is_update_ = false;
  NSAlert* __strong alert_ = nil;
  base::WeakPtrFactory<ACPasswordsUI> weak_factory_{this};

  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

}  // namespace argon_core

#endif  // ARGON_CORE_BROWSER_AC_PASSWORDS_UI_H_
