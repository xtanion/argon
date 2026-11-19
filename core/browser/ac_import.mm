// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#import "argon_core/public/ACImport.h"

#include <algorithm>
#include <optional>
#include <utility>
#include <vector>

#import "argon_core/browser/ac_internal.h"
#include "base/barrier_callback.h"
#include "base/functional/bind.h"
#include "base/strings/sys_string_conversions.h"
#include "base/time/time.h"
#include "chrome/browser/history/history_service_factory.h"
#include "chrome/browser/password_manager/factories/profile_password_store_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "components/history/core/browser/history_service.h"
#include "components/history/core/browser/url_row.h"
#include "components/keyed_service/core/service_access_type.h"
#include "components/password_manager/core/browser/password_store/password_store_interface.h"
#include "components/password_manager/core/browser/password_store/stored_credential.h"
#include "content/public/browser/storage_partition.h"
#include "net/base/apple/url_conversions.h"
#include "net/cookies/canonical_cookie.h"
#include "net/cookies/cookie_access_result.h"
#include "net/cookies/cookie_constants.h"
#include "net/cookies/cookie_options.h"
#include "services/network/public/mojom/cookie_manager.mojom.h"
#include "url/gurl.h"

@implementation ACImportedVisit
@end

@implementation ACImportedLogin
@end

@implementation ACImportedCookie
@end

namespace {

base::Time TimeFrom(NSDate* date) {
  return date ? base::Time::FromNSDate(date) : base::Time();
}

net::CookieSameSite SameSiteFrom(NSInteger value) {
  switch (value) {
    case 0:
      return net::CookieSameSite::NO_RESTRICTION;
    case 1:
      return net::CookieSameSite::LAX_MODE;
    case 2:
      return net::CookieSameSite::STRICT_MODE;
    default:
      return net::CookieSameSite::UNSPECIFIED;
  }
}

net::CookiePriority PriorityFrom(NSInteger value) {
  switch (value) {
    case 0:
      return net::COOKIE_PRIORITY_LOW;
    case 2:
      return net::COOKIE_PRIORITY_HIGH;
    default:
      return net::COOKIE_PRIORITY_MEDIUM;
  }
}

net::CookieSourceScheme SourceSchemeFrom(NSInteger value) {
  switch (value) {
    case 1:
      return net::CookieSourceScheme::kNonSecure;
    case 2:
      return net::CookieSourceScheme::kSecure;
    default:
      return net::CookieSourceScheme::kUnset;
  }
}

net::CookieSourceType SourceTypeFrom(NSInteger value) {
  switch (value) {
    case 1:
      return net::CookieSourceType::kHTTP;
    case 2:
      return net::CookieSourceType::kScript;
    default:
      return net::CookieSourceType::kOther;
  }
}

}  // namespace

@implementation ACProfile (Import)

- (void)importHistory:(NSArray<ACImportedVisit*>*)visits {
  history::HistoryService* service = HistoryServiceFactory::GetForProfile(
      self.nativeProfile, ServiceAccessType::EXPLICIT_ACCESS);
  if (!service) {
    return;
  }
  history::URLRows rows;
  rows.reserve(visits.count);
  for (ACImportedVisit* visit in visits) {
    GURL url = net::GURLWithNSURL(visit.url);
    if (!url.is_valid()) {
      continue;
    }
    history::URLRow row(url);
    row.set_title(base::SysNSStringToUTF16(visit.title ?: @""));
    row.set_visit_count(std::max<int>(1, visit.visitCount));
    row.set_typed_count(std::max<int>(0, visit.typedCount));
    row.set_last_visit(TimeFrom(visit.lastVisit));
    row.set_hidden(false);
    rows.push_back(std::move(row));
  }
  if (!rows.empty()) {
    service->AddPagesWithDetails(rows, history::SOURCE_BROWSED);
  }
}

- (void)importLogins:(NSArray<ACImportedLogin*>*)logins
          completion:(void (^)(void))completion {
  scoped_refptr<password_manager::PasswordStoreInterface> store =
      ProfilePasswordStoreFactory::GetForProfile(
          self.nativeProfile, ServiceAccessType::EXPLICIT_ACCESS);
  if (!store) {
    completion();
    return;
  }
  std::vector<password_manager::StoredCredential> forms;
  for (ACImportedLogin* login in logins) {
    GURL url = net::GURLWithNSURL(login.url);
    if (!url.is_valid() || login.signonRealm.length == 0) {
      continue;
    }
    password_manager::StoredCredential form;
    form.scheme = password_manager::PasswordForm::Scheme::kHtml;
    form.type = password_manager::PasswordForm::Type::kImported;
    form.in_store = password_manager::PasswordForm::Store::kProfileStore;
    form.signon_realm = base::SysNSStringToUTF8(login.signonRealm);
    form.url = url;
    if (login.actionURL) {
      form.action = net::GURLWithNSURL(login.actionURL);
    }
    form.username_element = base::SysNSStringToUTF16(login.usernameElement ?: @"");
    form.username_value = base::SysNSStringToUTF16(login.username ?: @"");
    form.password_element = base::SysNSStringToUTF16(login.passwordElement ?: @"");
    form.password_value = password_manager::PasswordString(
        base::SysNSStringToUTF16(login.password ?: @""));
    base::Time created = TimeFrom(login.dateCreated);
    form.date_created = created.is_null() ? base::Time::Now() : created;
    form.date_password_modified = form.date_created;
    form.date_last_used = TimeFrom(login.dateLastUsed);
    form.times_used_in_html_form = static_cast<int>(login.timesUsed);
    forms.push_back(std::move(form));
  }
  if (forms.empty()) {
    completion();
    return;
  }
  store->AddLogins(std::move(forms), base::BindOnce(^{
                     completion();
                   }));
}

- (void)importCookies:(NSArray<ACImportedCookie*>*)cookies
           completion:(void (^)(NSInteger imported))completion {
  network::mojom::CookieManager* manager =
      self.nativeProfile->GetDefaultStoragePartition()
          ->GetCookieManagerForBrowserProcess();
  std::vector<std::pair<net::CanonicalCookie, GURL>> parsed;
  for (ACImportedCookie* cookie in cookies) {
    std::string domain = base::SysNSStringToUTF8(cookie.domain);
    std::string host = domain.starts_with(".") ? domain.substr(1) : domain;
    std::string path = base::SysNSStringToUTF8(cookie.path.length ? cookie.path : @"/");
    std::unique_ptr<net::CanonicalCookie> canonical =
        net::CanonicalCookie::FromStorage(
            base::SysNSStringToUTF8(cookie.name),
            base::SysNSStringToUTF8(cookie.value), domain, path,
            TimeFrom(cookie.creation), TimeFrom(cookie.expiration),
            TimeFrom(cookie.lastAccess), TimeFrom(cookie.lastUpdate),
            cookie.secure, cookie.httpOnly, SameSiteFrom(cookie.sameSite),
            PriorityFrom(cookie.priority), std::nullopt,
            SourceSchemeFrom(cookie.sourceScheme),
            static_cast<int>(cookie.sourcePort),
            SourceTypeFrom(cookie.sourceType),
            net::CanonicalCookieFromStorageCallSite::kCookieManager);
    GURL source((cookie.secure ? "https://" : "http://") + host + path);
    if (!canonical || !source.is_valid()) {
      continue;
    }
    parsed.emplace_back(std::move(*canonical), std::move(source));
  }
  if (!manager || parsed.empty()) {
    completion(0);
    return;
  }
  auto barrier = base::BarrierCallback<bool>(
      parsed.size(), base::BindOnce(^(std::vector<bool> results) {
        completion(std::count(results.begin(), results.end(), true));
      }));
  for (auto& [cookie, source] : parsed) {
    manager->SetCanonicalCookie(
        cookie, source, net::CookieOptions::MakeAllInclusive(),
        base::BindOnce(
            [](base::RepeatingCallback<void(bool)> done,
               net::CookieAccessResult result) {
              done.Run(result.status.IsInclude());
            },
            barrier));
  }
}

@end
