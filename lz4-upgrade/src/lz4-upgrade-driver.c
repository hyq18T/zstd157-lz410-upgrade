/*
 * lz4-upgrade-driver.c
 *
 * Same-name high-priority lz4 crypto driver.
 *
 * Registers cra_name "lz4" with cra_driver_name "lz4-new-generic" and
 * cra_priority 100, so new crypto_alloc_base("lz4", ...) lookups from zram
 * select this 1.10.0 implementation instead of the kernel's built-in one.
 */

#define LZ4_STATIC_LINKING_ONLY

#include <linux/crypto.h>
#include <linux/errno.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/vmalloc.h>
#include <crypto/algapi.h>
#include "lz4.h"

struct lz4_upgrade_ctx {
	void *wmem;
	size_t wmem_size;
};

static int lz4_upgrade_init(struct crypto_tfm *tfm)
{
	struct lz4_upgrade_ctx *ctx = crypto_tfm_ctx(tfm);
	int state_size;

	state_size = LZ4_sizeofState();
	if (state_size <= 0)
		return -EINVAL;

	ctx->wmem = vmalloc((size_t)state_size);
	if (!ctx->wmem)
		return -ENOMEM;

	if (!LZ4_initStream(ctx->wmem, (size_t)state_size)) {
		vfree(ctx->wmem);
		ctx->wmem = NULL;
		return -EINVAL;
	}

	ctx->wmem_size = (size_t)state_size;
	return 0;
}

static void lz4_upgrade_exit(struct crypto_tfm *tfm)
{
	struct lz4_upgrade_ctx *ctx = crypto_tfm_ctx(tfm);

	if (ctx->wmem) {
		vfree(ctx->wmem);
		ctx->wmem = NULL;
	}
}

static int lz4_upgrade_compress(struct crypto_tfm *tfm,
				const u8 *src, unsigned int slen,
				u8 *dst, unsigned int *dlen)
{
	struct lz4_upgrade_ctx *ctx = crypto_tfm_ctx(tfm);
	int out;

	if (slen > INT_MAX || *dlen > INT_MAX)
		return -E2BIG;

	out = LZ4_compress_fast_extState_fastReset(ctx->wmem,
						   (const char *)src,
						   (char *)dst,
						   (int)slen, (int)*dlen, 1);
	if (out <= 0)
		return -EINVAL;

	*dlen = (unsigned int)out;
	return 0;
}

static int lz4_upgrade_decompress(struct crypto_tfm *tfm,
				  const u8 *src, unsigned int slen,
				  u8 *dst, unsigned int *dlen)
{
	int out;

	if (slen > INT_MAX || *dlen > INT_MAX)
		return -E2BIG;

	out = LZ4_decompress_safe((const char *)src, (char *)dst,
				  (int)slen, (int)*dlen);
	if (out < 0)
		return -EINVAL;

	*dlen = (unsigned int)out;
	return 0;
}

static struct crypto_alg lz4_upgrade_alg = {
	.cra_name		= "lz4",
	.cra_driver_name	= "lz4-new-generic",
	.cra_priority		= 100,
	.cra_flags		= CRYPTO_ALG_TYPE_COMPRESS,
	.cra_ctxsize		= sizeof(struct lz4_upgrade_ctx),
	.cra_module		= THIS_MODULE,
	.cra_init		= lz4_upgrade_init,
	.cra_exit		= lz4_upgrade_exit,
	.cra_u			= {
		.compress = {
			.coa_compress	= lz4_upgrade_compress,
			.coa_decompress	= lz4_upgrade_decompress,
		},
	},
};

static int __init lz4_upgrade_mod_init(void)
{
	return crypto_register_alg(&lz4_upgrade_alg);
}

static void __exit lz4_upgrade_mod_fini(void)
{
	crypto_unregister_alg(&lz4_upgrade_alg);
}

module_init(lz4_upgrade_mod_init);
module_exit(lz4_upgrade_mod_fini);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Same-name high-priority lz4 1.10.0 crypto driver");
MODULE_VERSION("1.10.0");
MODULE_ALIAS_CRYPTO("lz4");
