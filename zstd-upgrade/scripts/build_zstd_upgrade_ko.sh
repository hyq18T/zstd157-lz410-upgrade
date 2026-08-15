#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Build zstd-upgrade.ko for Xiaomi 15 Pro (haotian / 2410DPN6CC,
# kernel 6.6.77-android15-8-gca30f3b4bef6-abogki440974771-4k).
#
# The module embeds zstd 1.5.7 and registers it as cra_name "zstd" /
# cra_driver_name "zstd-new-generic" with cra_priority 100. The kernel's
# built-in zstd stays untouched.

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

headers_dir=${QCOM_HEADERS_DIR:-/mnt/c/Users/hyq-18T/Documents/Codex/2026-08-11/github/lz4kd-zram/build-kheaders}
clang=${QCOM_CLANG:-/usr/bin/clang}
linker=${QCOM_LD_LLD:-/usr/bin/ld.lld}
vermagic=${QCOM_VERMAGIC:-"6.6.77-android15-8-gca30f3b4bef6-abogki440974771-4k SMP preempt mod_unload modversions aarch64"}
output_dir=${QCOM_OUTPUT_DIR:-$project_root/out}
module_name=${QCOM_MODULE_NAME:-zstd-upgrade}
output_name=${QCOM_OUTPUT_NAME:-zstd-upgrade}
versions_header=$output_dir/${output_name}_versions.h
module_meta=$output_dir/${output_name}_mod.c
module_lds=$output_dir/module.lds

fail() {
	echo "error: $*" >&2
	exit 1
}

[ -n "$clang" ] || fail "QCOM_CLANG is required"
[ -n "$linker" ] || fail "QCOM_LD_LLD is required"
[ -f "$project_root/src/zstd-upgrade-driver.c" ] || fail "missing driver source"
[ -d "$project_root/lib/zstd" ] || fail "missing zstd lib source"
[ -f "$headers_dir/include/linux/compiler-version.h" ] || fail "incomplete kernel headers"
[ -f "$headers_dir/include/linux/kconfig.h" ] || fail "incomplete kernel headers"
[ -x "$clang" ] || fail "clang not executable: $clang"
[ -x "$linker" ] || fail "ld.lld not executable: $linker"

mkdir -p "$output_dir"

cat > "$versions_header" <<EOF
#ifndef ZSTD_UPGRADE_VERSIONS_H
#define ZSTD_UPGRADE_VERSIONS_H
#define ZSTD_UPGRADE_VERMAGIC "$vermagic"
static const struct modversion_info ____versions[] __used __section("__versions") = {
    { 0x4e276f37, "module_layout" },
    { 0x30f4deab, "crypto_register_alg" },
    { 0x94876ded, "crypto_unregister_alg" },
    { 0xd6ee688f, "vmalloc" },
    { 0x999e8297, "vfree" },
    { 0xdcb764ad, "memset" },
    { 0x4829a47e, "memcpy" },
    { 0x5a9f1d63, "memmove" },
};
#endif
EOF

lds_header=$headers_dir/arch/arm64/include/asm/module.lds.h
[ -f "$lds_header" ] || fail "missing arm64 module linker fragment: $lds_header"
$clang --target=aarch64-linux-gnu -E -P -x assembler-with-cpp \
	-D__KERNEL__ -D__ASSEMBLY__ \
	-include "$headers_dir/include/linux/compiler-version.h" \
	-include "$headers_dir/include/linux/kconfig.h" \
	-I"$headers_dir/arch/arm64/include" -I"$headers_dir/arch/arm64/include/generated" \
	-I"$headers_dir/include" -I"$headers_dir/arch/arm64/include/uapi" \
	-I"$headers_dir/arch/arm64/include/generated/uapi" \
	-I"$headers_dir/include/uapi" -I"$headers_dir/include/generated/uapi" \
	"$lds_header" -o "$module_lds"

{
	printf '%s\n' '#include <linux/module.h>'
	printf '%s\n' '#include "zstd-upgrade_versions.h"'
	printf '%s\n' 'struct module __this_module'
	printf '%s\n' '__section(".gnu.linkonce.this_module") = {'
	printf '    .name = "%s",\n' "$module_name"
	printf '%s\n' '    .init = init_module,'
	printf '%s\n' '#ifdef CONFIG_MODULE_UNLOAD'
	printf '%s\n' '    .exit = cleanup_module,'
	printf '%s\n' '#endif'
	printf '%s\n' '    .arch = MODULE_ARCH_INIT,' '};'
	printf 'MODULE_INFO(name, "%s");\n' "$module_name"
	printf 'MODULE_INFO(vermagic, ZSTD_UPGRADE_VERMAGIC);\n'
} > "$module_meta"

common_flags="--target=aarch64-linux-gnu -std=gnu11 -O2 \
	-D__KERNEL__ -DMODULE \
	-DKBUILD_MODNAME=\"$module_name\" -DKBUILD_BASENAME=\"$module_name\" \
	-include $headers_dir/include/linux/compiler-version.h \
	-include $headers_dir/include/linux/kconfig.h \
	-I$output_dir -I$project_root/include -I$project_root/src -I$project_root/lib/zstd \
	-I$headers_dir/arch/arm64/include -I$headers_dir/arch/arm64/include/generated \
	-I$headers_dir/include -I$headers_dir/arch/arm64/include/uapi \
	-I$headers_dir/arch/arm64/include/generated/uapi \
	-I$headers_dir/include/uapi -I$headers_dir/include/generated/uapi \
	-DZSTD_LINUX_KERNEL -DZSTD_NO_INTRINSICS -DZSTD_DISABLE_ASM \
	-DZSTD_NO_UNUSED_FUNCTIONS -DZSTD_STATIC_LINKING_ONLY \
	-DFSE_STATIC_LINKING_ONLY -DXXH_STATIC_LINKING_ONLY \
	-DZSTD_LEGACY_SUPPORT=0 -DZSTD_COMPRESS_HEAPMODE=1 \
	-DZSTD_HAVE_WEAK_SYMBOLS=0 -DZSTD_TRACE=0 -DZSTD_NO_TRACE \
	-DSTATIC_BMI2=0 \
	-fno-pic -fno-PIE -fno-common -fno-builtin \
	-fno-stack-protector -fno-asynchronous-unwind-tables \
	-fno-unwind-tables -fno-delete-null-pointer-checks \
	-fno-strict-overflow -fno-optimize-sibling-calls \
	-fno-omit-frame-pointer -ffixed-x18 \
	-fsanitize=kcfi \
	-mbranch-protection=pac-ret -mgeneral-regs-only -mstrict-align \
	-mno-outline-atomics -mcmodel=large"

objects=""
for src in \
	"$project_root/src/zstd-upgrade-driver.c" \
	"$project_root/lib/zstd/common/debug.c" \
	"$project_root/lib/zstd/common/entropy_common.c" \
	"$project_root/lib/zstd/common/error_private.c" \
	"$project_root/lib/zstd/common/fse_decompress.c" \
	"$project_root/lib/zstd/common/xxhash.c" \
	"$project_root/lib/zstd/common/zstd_common.c" \
	"$project_root/lib/zstd/compress/fse_compress.c" \
	"$project_root/lib/zstd/compress/hist.c" \
	"$project_root/lib/zstd/compress/huf_compress.c" \
	"$project_root/lib/zstd/compress/zstd_compress.c" \
	"$project_root/lib/zstd/compress/zstd_compress_literals.c" \
	"$project_root/lib/zstd/compress/zstd_compress_sequences.c" \
	"$project_root/lib/zstd/compress/zstd_compress_superblock.c" \
	"$project_root/lib/zstd/compress/zstd_double_fast.c" \
	"$project_root/lib/zstd/compress/zstd_fast.c" \
	"$project_root/lib/zstd/compress/zstd_lazy.c" \
	"$project_root/lib/zstd/compress/zstd_ldm.c" \
	"$project_root/lib/zstd/compress/zstd_opt.c" \
	"$project_root/lib/zstd/compress/zstd_preSplit.c" \
	"$project_root/lib/zstd/decompress/huf_decompress.c" \
	"$project_root/lib/zstd/decompress/zstd_ddict.c" \
	"$project_root/lib/zstd/decompress/zstd_decompress.c" \
	"$project_root/lib/zstd/decompress/zstd_decompress_block.c"
do
	base=$(basename "$src" .c)
	# shellcheck disable=SC2086
	$clang $common_flags -c "$src" -o "$output_dir/$base.o"
	objects="$objects $output_dir/$base.o"
done

# shellcheck disable=SC2086
$clang $common_flags -c "$module_meta" -o "$output_dir/${output_name}_mod.o"
objects="$objects $output_dir/${output_name}_mod.o"

# shellcheck disable=SC2086
$linker -r -m aarch64elf -z noexecstack --build-id=sha1 \
	-T "$module_lds" \
	-o "$output_dir/$output_name.ko" $objects

strip=${QCOM_STRIP:-/usr/bin/llvm-strip}
[ -x "$strip" ] || fail "strip not executable: $strip"
"$strip" --strip-unneeded "$output_dir/$output_name.ko"

echo "vermagic: $vermagic"
echo "output:   $output_dir/$output_name.ko"
