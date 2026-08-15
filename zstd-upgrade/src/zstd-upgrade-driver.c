/*
 * zstd-upgrade-driver.c
 *
 * Same-name high-priority zstd crypto driver.
 *
 * Registers cra_name "zstd" with cra_driver_name "zstd-new-generic" and
 * cra_priority 100, so new crypto_alloc_base("zstd", ...) lookups from zram
 * select this 1.5.7 implementation instead of the kernel's built-in one.
 */

#define ZSTD_STATIC_LINKING_ONLY

#include <linux/errno.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/crypto.h>
#include <linux/vmalloc.h>
#include <crypto/algapi.h>
#include <linux/zstd_lib.h>

#define ZSTD_UPGRADE_LEVEL 3

struct zstd_upgrade_ctx {
	ZSTD_CCtx *cctx;
	ZSTD_DCtx *dctx;
};

static void *zstd_upgrade_alloc(void *opaque, size_t size)
{
	return vmalloc(size);
}

static void zstd_upgrade_free(void *opaque, void *address)
{
	vfree(address);
}

static ZSTD_customMem zstd_upgrade_mem = {
	.customAlloc = zstd_upgrade_alloc,
	.customFree = zstd_upgrade_free,
	.opaque = NULL,
};

static int zstd_upgrade_init(struct crypto_tfm *tfm)
{
	struct zstd_upgrade_ctx *ctx = crypto_tfm_ctx(tfm);

	ctx->cctx = ZSTD_createCCtx_advanced(zstd_upgrade_mem);
	if (!ctx->cctx)
		return -ENOMEM;

	ctx->dctx = ZSTD_createDCtx_advanced(zstd_upgrade_mem);
	if (!ctx->dctx) {
		ZSTD_freeCCtx(ctx->cctx);
		return -ENOMEM;
	}

	return 0;
}

static void zstd_upgrade_exit(struct crypto_tfm *tfm)
{
	struct zstd_upgrade_ctx *ctx = crypto_tfm_ctx(tfm);

	ZSTD_freeDCtx(ctx->dctx);
	ZSTD_freeCCtx(ctx->cctx);
}

static int zstd_upgrade_compress(struct crypto_tfm *tfm,
				 const u8 *src, unsigned int slen,
				 u8 *dst, unsigned int *dlen)
{
	struct zstd_upgrade_ctx *ctx = crypto_tfm_ctx(tfm);
	size_t out;

	out = ZSTD_compressCCtx(ctx->cctx, dst, *dlen, src, slen,
				ZSTD_UPGRADE_LEVEL);
	if (ZSTD_isError(out) || out > UINT_MAX)
		return -EINVAL;

	*dlen = (unsigned int)out;
	return 0;
}

static int zstd_upgrade_decompress(struct crypto_tfm *tfm,
				   const u8 *src, unsigned int slen,
				   u8 *dst, unsigned int *dlen)
{
	struct zstd_upgrade_ctx *ctx = crypto_tfm_ctx(tfm);
	size_t out;

	out = ZSTD_decompressDCtx(ctx->dctx, dst, *dlen, src, slen);
	if (ZSTD_isError(out) || out > UINT_MAX)
		return -EINVAL;

	*dlen = (unsigned int)out;
	return 0;
}

static struct crypto_alg zstd_upgrade_alg = {
	.cra_name		= "zstd",
	.cra_driver_name	= "zstd-new-generic",
	.cra_priority		= 100,
	.cra_flags		= CRYPTO_ALG_TYPE_COMPRESS,
	.cra_ctxsize		= sizeof(struct zstd_upgrade_ctx),
	.cra_module		= THIS_MODULE,
	.cra_init		= zstd_upgrade_init,
	.cra_exit		= zstd_upgrade_exit,
	.cra_u			= {
		.compress = {
			.coa_compress	= zstd_upgrade_compress,
			.coa_decompress	= zstd_upgrade_decompress,
		},
	},
};

static int __init zstd_upgrade_mod_init(void)
{
	return crypto_register_alg(&zstd_upgrade_alg);
}

static void __exit zstd_upgrade_mod_fini(void)
{
	crypto_unregister_alg(&zstd_upgrade_alg);
}

module_init(zstd_upgrade_mod_init);
module_exit(zstd_upgrade_mod_fini);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Same-name high-priority zstd 1.5.7 crypto driver");
MODULE_VERSION("1.5.7");
MODULE_ALIAS_CRYPTO("zstd");
