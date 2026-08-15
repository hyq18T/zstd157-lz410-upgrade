#ifndef LZ4_UPGRADE_LIMITS_H
#define LZ4_UPGRADE_LIMITS_H

/*
 * Minimal limits.h shim for lz4 1.10.0 when compiled as a Linux kernel
 * module. Kernel headers do not ship a userspace-style limits.h.
 */

#define CHAR_BIT 8

#define SCHAR_MIN (-128)
#define SCHAR_MAX 127
#define UCHAR_MAX 255

#define SHRT_MIN (-32768)
#define SHRT_MAX 32767
#define USHRT_MAX 65535

#define INT_MIN (-INT_MAX - 1)
#define INT_MAX 2147483647
#define UINT_MAX 4294967295U

#define LONG_MIN (-LONG_MAX - 1)
#define LONG_MAX 9223372036854775807L
#define ULONG_MAX 18446744073709551615UL

#define LLONG_MIN (-LLONG_MAX - 1)
#define LLONG_MAX 9223372036854775807LL
#define ULLONG_MAX 18446744073709551615ULL

#endif
