// Copyright 2026 The Argon Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef ARGON_CORE_PUBLIC_ACEXPORT_H_
#define ARGON_CORE_PUBLIC_ACEXPORT_H_

#ifdef __cplusplus
#define AC_EXTERN extern "C"
#else
#define AC_EXTERN extern
#endif

#define AC_EXPORT AC_EXTERN __attribute__((visibility("default")))
#define AC_OBJC_EXPORT __attribute__((visibility("default")))

#endif  // ARGON_CORE_PUBLIC_ACEXPORT_H_
