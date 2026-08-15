#!/system/bin/sh
# Verify that zstd 1.5.7 and lz4 1.10.0 requests hit the new crypto drivers.

MODDIR=${0%/*}
ZKO="$MODDIR/zstd-upgrade.ko"
LKO="$MODDIR/lz4-upgrade.ko"
CTRL=/sys/class/zram-control
ZDRIVER=zstd-new-generic
LDRIVER=lz4-new-generic

module_is_loaded() {
	grep -Eq "$1" /proc/modules 2>/dev/null
}

driver_block() {
	awk -v drv="$1" 'BEGIN { RS="" } $0 ~ drv { print $0 }' /proc/crypto 2>/dev/null
}

refcnt_of() {
	driver_block "$1" | awk '/^refcnt/ { print $3; exit }'
}

echo "=== 1. modules and embedded versions ==="
if module_is_loaded '^zstd(_|-)?upgrade '; then
	echo "zstd module: loaded"
else
	echo "zstd module: NOT loaded"
fi
if module_is_loaded '^lz4(_|-)?upgrade '; then
	echo "lz4 module: loaded"
else
	echo "lz4 module: NOT loaded"
fi
grep -m1 -a "1.5.7" "$ZKO" >/dev/null 2>&1 && echo "zstd ko contains version string: 1.5.7"
grep -m1 -a "1.10.0" "$LKO" >/dev/null 2>&1 && echo "lz4 ko contains version string: 1.10.0"

echo
echo "=== 2. crypto registration ==="
for pair in "$ZDRIVER:zstd" "$LDRIVER:lz4"; do
	driver=${pair%%:*}
	algo=${pair##*:}
	if driver_block "$driver" | grep -q "driver[[:space:]]*: $driver"; then
		echo "crypto driver $algo: present ($driver)"
		driver_block "$driver"
	else
		echo "crypto driver $algo: MISSING ($driver)"
	fi
done

echo
echo "=== 3. live refcnt proof on a temporary zram ==="
if [ ! -r "$CTRL/hot_add" ]; then
	echo "zram-control hot_add not available, skip live proof"
	exit 0
fi
before_z=$(refcnt_of "$ZDRIVER")
before_l=$(refcnt_of "$LDRIVER")
zram_no=$(cat "$CTRL/hot_add")
case "$zram_no" in
	''|*[!0-9]*|0)
		echo "hot_add returned invalid id: $zram_no"
		exit 1
		;;
esac
dev=/sys/block/zram$zram_no
pass=1

echo "--- zstd test ---"
if echo zstd > "$dev/comp_algorithm" 2>/dev/null; then
	echo 16M > "$dev/disksize" 2>/dev/null
	after_z=$(refcnt_of "$ZDRIVER")
	echo "refcnt before: ${before_z:-unknown}, after: ${after_z:-unknown}"
	if [ -n "$after_z" ] && [ -n "$before_z" ] && [ "$after_z" -gt "$before_z" ]; then
		echo "proof: PASS (zstd request hit $ZDRIVER)"
	else
		echo "proof: FAIL (refcnt did not increase)"
		pass=0
	fi
else
	echo "proof: FAIL (could not select zstd on zram$zram_no)"
	pass=0
fi
echo 1 > "$dev/reset" 2>/dev/null

echo "--- lz4 test ---"
if echo lz4 > "$dev/comp_algorithm" 2>/dev/null; then
	echo 16M > "$dev/disksize" 2>/dev/null
	after_l=$(refcnt_of "$LDRIVER")
	echo "refcnt before: ${before_l:-unknown}, after: ${after_l:-unknown}"
	if [ -n "$after_l" ] && [ -n "$before_l" ] && [ "$after_l" -gt "$before_l" ]; then
		echo "proof: PASS (lz4 request hit $LDRIVER)"
	else
		echo "proof: FAIL (refcnt did not increase)"
		pass=0
	fi
else
	echo "proof: FAIL (could not select lz4 on zram$zram_no)"
	pass=0
fi
echo 1 > "$dev/reset" 2>/dev/null
echo "$zram_no" > "$CTRL/hot_remove" 2>/dev/null
echo "temp zram$zram_no removed"
[ "$pass" -eq 1 ]
