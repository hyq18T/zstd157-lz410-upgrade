#ifndef LZ4_UPGRADE_STDINT_H
#define LZ4_UPGRADE_STDINT_H

/*
 * Minimal stdint.h shim for lz4 1.10.0 when compiled as a Linux kernel
 * module. Kernel headers do not ship a userspace-style stdint.h.
 */

typedef signed char        int8_t;
typedef unsigned char      uint8_t;
typedef signed short       int16_t;
typedef unsigned short     uint16_t;
typedef signed int         int32_t;
typedef unsigned int       uint32_t;
typedef signed long long   int64_t;
typedef unsigned long long uint64_t;
typedef signed long        intptr_t;
typedef unsigned long      uintptr_t;

#endif
