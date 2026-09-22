#!/bin/sh
# 为小米 15 Pro 当前内核重新编译 zstd 1.5.7 + lz4 1.10.0 两个 .ko
#
# 用法（在 WSL Ubuntu 里）：
#   sh BUILD-6.6.118.sh /path/to/zstd157-lz410-upgrade /path/to/kernel-headers
#
# 换内核时的检查清单：
#   1) headers 必须来自运行内核：adb shell su -c 'cat /sys/kernel/kheaders.tar.xz' > kheaders.tar.xz
#      并确认 sha256 与手机上一致，解压后 include/config 里 kernel.release == uname -r
#   2) QCOM_VERMAGIC 用 uname -r 拼出来（后缀固定 " SMP preempt mod_unload modversions aarch64"）
#   3) 符号 CRC 见 build_zstd_upgrade_ko.sh 里写死的那张表：换内核后要用真机 vendor .ko 的
#      __versions 段重新核对（见 验证记录-v1.9.txt 第 2 节的方法）
#   4) clang 大版本要和内核构建用的 clang 大版本一致（内核是 18.0.0，本机 WSL 是 18.1.3），
#      因为 CONFIG_CFI_CLANG=y，KCFI typeid 由编译器算出

set -eu

SRC=${1:?需要源码目录}
HDR=${2:?需要内核 headers 目录}
OUT=${OUT:-$PWD/out}
VERMAGIC=${VERMAGIC:-6.6.118-android15-8-gc44b714366cc-abogki519650608-4k SMP preempt mod_unload modversions aarch64}

export QCOM_HEADERS_DIR="$HDR"
export QCOM_VERMAGIC="$VERMAGIC"
export QCOM_CLANG=${QCOM_CLANG:-/usr/bin/clang}
export QCOM_LD_LLD=${QCOM_LD_LLD:-/usr/bin/ld.lld}
export QCOM_STRIP=${QCOM_STRIP:-/usr/bin/llvm-strip}

[ -f "$SRC/zstd-upgrade/scripts/build_zstd_upgrade_ko.sh" ] || { echo "源码目录不对: $SRC"; exit 1; }
[ -f "$HDR/include/linux/compiler-version.h" ] || { echo "headers 不完整: $HDR"; exit 1; }

mkdir -p "$OUT/zstd" "$OUT/lz4"

QCOM_OUTPUT_DIR="$OUT/zstd" sh "$SRC/zstd-upgrade/scripts/build_zstd_upgrade_ko.sh"
QCOM_OUTPUT_DIR="$OUT/lz4"  sh "$SRC/lz4-upgrade/scripts/build_lz4_upgrade_ko.sh"

echo
echo "vermagic: $VERMAGIC"
ls -l "$OUT/zstd/zstd-upgrade.ko" "$OUT/lz4/lz4-upgrade.ko"
sha256sum "$OUT/zstd/zstd-upgrade.ko" "$OUT/lz4/lz4-upgrade.ko"
