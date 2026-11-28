// Copyright 2026 The Stone Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

#ifndef STONE_CORE_PUBLIC_ACEXPORT_H_
#define STONE_CORE_PUBLIC_ACEXPORT_H_

#ifdef __cplusplus
#define AC_EXTERN extern "C"
#else
#define AC_EXTERN extern
#endif

#define AC_EXPORT AC_EXTERN __attribute__((visibility("default")))
#define AC_OBJC_EXPORT __attribute__((visibility("default")))

#endif  // STONE_CORE_PUBLIC_ACEXPORT_H_
