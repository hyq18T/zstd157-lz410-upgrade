// SPDX-License-Identifier: GPL-2.0+ OR BSD-3-Clause
/*
 * xxHash - Extremely Fast Hash algorithm
 * Copyright (c) Yann Collet - Meta Platforms, Inc
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

/*
 * Module-local xxh64 implementation.
 *
 * zstd 1.5.6 source calls the kernel's xxh64 API (linux/xxhash.h), but the
 * kernel does not export xxh64/xxh64_reset/xxh64_update/xxh64_digest to
 * modules.  This file provides those four symbols inside the module so the
 * built-in kernel xxhash does not need to be resolved at load time.
 *
 * The layout must match include/linux/xxhash.h exactly (v1..v4 are separate
 * fields, not the upstream xxhash.h v[4] array), so the algorithm below is
 * written directly against that layout instead of reusing lib/zstd's
 * common/xxhash.h.
 */

#include <linux/xxhash.h>
#include <linux/errno.h>
#include <linux/string.h>
#include <asm/unaligned.h>

#define XXH_PRIME64_1 0x9E3779B185EBCA87ULL
#define XXH_PRIME64_2 0xC2B2AE3D27D4EB4FULL
#define XXH_PRIME64_3 0x165667B19E3779F9ULL
#define XXH_PRIME64_4 0x85EBCA77C2B2AE63ULL
#define XXH_PRIME64_5 0x27D4EB2F165667C5ULL

static inline uint64_t xxh64_rotl(uint64_t x, int r)
{
	return (x << r) | (x >> (64 - r));
}

static uint64_t xxh64_round(uint64_t acc, uint64_t input)
{
	acc += input * XXH_PRIME64_2;
	acc = xxh64_rotl(acc, 31);
	acc *= XXH_PRIME64_1;
	return acc;
}

static uint64_t xxh64_merge_round(uint64_t acc, uint64_t val)
{
	val = xxh64_round(0, val);
	acc ^= val;
	acc = acc * XXH_PRIME64_1 + XXH_PRIME64_4;
	return acc;
}

static uint64_t xxh64_avalanche(uint64_t hash)
{
	hash ^= hash >> 33;
	hash *= XXH_PRIME64_2;
	hash ^= hash >> 29;
	hash *= XXH_PRIME64_3;
	hash ^= hash >> 32;
	return hash;
}

static uint64_t xxh64_finalize(uint64_t hash, const uint8_t *ptr, size_t len)
{
	len &= 31;
	while (len >= 8) {
		uint64_t k1 = xxh64_round(0, get_unaligned_le64(ptr));

		ptr += 8;
		hash ^= k1;
		hash = xxh64_rotl(hash, 27) * XXH_PRIME64_1 + XXH_PRIME64_4;
		len -= 8;
	}
	if (len >= 4) {
		uint32_t k1 = get_unaligned_le32(ptr);

		hash ^= (uint64_t)k1 * XXH_PRIME64_1;
		ptr += 4;
		hash = xxh64_rotl(hash, 23) * XXH_PRIME64_2 + XXH_PRIME64_3;
		len -= 4;
	}
	while (len > 0) {
		hash ^= (uint64_t)*ptr++ * XXH_PRIME64_5;
		hash = xxh64_rotl(hash, 11) * XXH_PRIME64_1;
		--len;
	}
	return xxh64_avalanche(hash);
}

void xxh64_reset(struct xxh64_state *state, uint64_t seed)
{
	__builtin_memset(state, 0, sizeof(*state));
	state->v1 = seed + XXH_PRIME64_1 + XXH_PRIME64_2;
	state->v2 = seed + XXH_PRIME64_2;
	state->v3 = seed;
	state->v4 = seed - XXH_PRIME64_1;
}

int xxh64_update(struct xxh64_state *state, const void *input, size_t length)
{
	const uint8_t *p = input;
	const uint8_t *end;

	if (input == NULL) {
		if (length != 0)
			return -EINVAL;
		return 0;
	}

	end = p + length;
	state->total_len += length;

	if (state->memsize + length < 32) {
		__builtin_memcpy((uint8_t *)state->mem64 + state->memsize,
				 input, length);
		state->memsize += (uint32_t)length;
		return 0;
	}

	if (state->memsize) {
		size_t fill = 32 - state->memsize;

		__builtin_memcpy((uint8_t *)state->mem64 + state->memsize,
				 input, fill);
		state->v1 = xxh64_round(state->v1,
					get_unaligned_le64(&state->mem64[0]));
		state->v2 = xxh64_round(state->v2,
					get_unaligned_le64(&state->mem64[1]));
		state->v3 = xxh64_round(state->v3,
					get_unaligned_le64(&state->mem64[2]));
		state->v4 = xxh64_round(state->v4,
					get_unaligned_le64(&state->mem64[3]));
		p += fill;
		state->memsize = 0;
	}

	while (p + 32 <= end) {
		state->v1 = xxh64_round(state->v1, get_unaligned_le64(p));
		p += 8;
		state->v2 = xxh64_round(state->v2, get_unaligned_le64(p));
		p += 8;
		state->v3 = xxh64_round(state->v3, get_unaligned_le64(p));
		p += 8;
		state->v4 = xxh64_round(state->v4, get_unaligned_le64(p));
		p += 8;
	}

	if (p < end) {
		__builtin_memcpy(state->mem64, p, (size_t)(end - p));
		state->memsize = (uint32_t)(end - p);
	}

	return 0;
}

uint64_t xxh64_digest(const struct xxh64_state *state)
{
	uint64_t h64;

	if (state->total_len >= 32) {
		h64 = xxh64_rotl(state->v1, 1) +
		      xxh64_rotl(state->v2, 7) +
		      xxh64_rotl(state->v3, 12) +
		      xxh64_rotl(state->v4, 18);
		h64 = xxh64_merge_round(h64, state->v1);
		h64 = xxh64_merge_round(h64, state->v2);
		h64 = xxh64_merge_round(h64, state->v3);
		h64 = xxh64_merge_round(h64, state->v4);
	} else {
		h64 = state->v3 + XXH_PRIME64_5;
	}

	h64 += state->total_len;
	return xxh64_finalize(h64, (const uint8_t *)state->mem64,
			      state->total_len);
}

uint64_t xxh64(const void *input, size_t length, uint64_t seed)
{
	struct xxh64_state state;

	xxh64_reset(&state, seed);
	xxh64_update(&state, input, length);
	return xxh64_digest(&state);
}
