#!/system/bin/sh
# Control script for zstd 1.5.7 + lz4 1.10.0 upgrade.
# Usage: sh zstd-upgrade.sh {status|load|unload}

MODDIR=${0%/*}
ZKO="$MODDIR/zstd-upgrade.ko"
LKO="$MODDIR/lz4-upgrade.ko"
CTRL=/sys/class/zram-control
ZDRIVER=zstd-new-generic
LDRIVER=lz4-new-generic

module_is_loaded() {
	grep -Eq "$1" /proc/modules 2>/dev/null
}

crypto_driver() {
	awk -v drv="$1" 'BEGIN { RS="" } $0 ~ drv { print $0 }' /proc/crypto 2>/dev/null
}

load_algo() {
	label=$1
	ko=$2
	module_pat=$3
	driver=$4
	if module_is_loaded "$module_pat"; then
		echo "[$label] already loaded"
		return 0
	fi
	if [ ! -f "$ko" ]; then
		echo "[$label] missing $ko"
		return 1
	fi
	if ! insmod "$ko"; then
		echo "[$label] insmod failed"
		return 1
	fi
	if ! crypto_driver "$driver" | grep -q "driver[[:space:]]*: $driver"; then
		echo "[$label] insmod ok but $driver missing from /proc/crypto"
		return 1
	fi
	echo "[$label] loaded, $driver registered"
}

unload_algo() {
	label=$1
	module_pat=$2
	mod_name=$3
	if ! module_is_loaded "$module_pat"; then
		echo "[$label] not loaded"
		return 0
	fi
	if ! rmmod "$mod_name" 2>/dev/null && ! rmmod "$label" 2>/dev/null; then
		echo "[$label] rmmod failed, maybe a zram device is using it"
		return 1
	fi
	echo "[$label] unloaded"
}

status() {
	echo "=== zstd-upgrade module ==="
	if module_is_loaded '^zstd(_|-)?upgrade '; then
		echo "zstd module: loaded"
	else
		echo "zstd module: not loaded"
	fi
	echo "zstd crypto driver ($ZDRIVER):"
	crypto_driver "$ZDRIVER"
	echo "builtin zstd driver:"
	awk 'BEGIN { RS="" } /name[[:space:]]*: zstd/ && /driver[[:space:]]*: zstd-generic/ { print $0 }' /proc/crypto 2>/dev/null

	echo
	echo "=== lz4-upgrade module ==="
	if module_is_loaded '^lz4(_|-)?upgrade '; then
		echo "lz4 module: loaded"
	else
		echo "lz4 module: not loaded"
	fi
	echo "lz4 crypto driver ($LDRIVER):"
	crypto_driver "$LDRIVER"
	echo "builtin lz4 drivers:"
	awk 'BEGIN { RS="" } /name[[:space:]]*: lz4/ && (/driver[[:space:]]*: lz4-generic/ || /driver[[:space:]]*: lz4-scomp/) { print $0 }' /proc/crypto 2>/dev/null

	echo
	echo "=== zram devices ==="
	for d in /sys/block/zram*; do
		[ -d "$d" ] || continue
		algo=$(cat "$d/comp_algorithm" 2>/dev/null)
		echo "$d: $algo"
	done
}

case "$1" in
	status) status ;;
	load)
		load_algo lz4-upgrade "$LKO" '^lz4(_|-)?upgrade ' "$LDRIVER" || exit $?
		load_algo zstd-upgrade "$ZKO" '^zstd(_|-)?upgrade ' "$ZDRIVER" || exit $?
		;;
	unload)
		unload_algo lz4-upgrade '^lz4(_|-)?upgrade ' lz4_upgrade || exit $?
		unload_algo zstd-upgrade '^zstd(_|-)?upgrade ' zstd_upgrade || exit $?
		;;
	*)
		echo "usage: sh ${0##*/} status|load|unload"
		;;
esac
