#!/system/bin/sh
# 验证：.ko 是否匹配当前内核、新驱动是否注册、新建 zram 是否真的命中新驱动

MODDIR=${0%/*}
BASE=${MODDIR%/bin}
ZKO="$MODDIR/zstd-upgrade.ko"
LKO="$MODDIR/lz4-upgrade.ko"
CTRL=/sys/class/zram-control
ZDRIVER=zstd-new-generic
LDRIVER=lz4-new-generic
pass=1

module_is_loaded() {
	grep -Eq "$1" /proc/modules 2>/dev/null
}

driver_block() {
	awk -v drv="$1" 'BEGIN { RS="" } $0 ~ drv { print $0 }' /proc/crypto 2>/dev/null
}

refcnt_of() {
	driver_block "$1" | awk '/^refcnt/ { print $3; exit }'
}

# Android toybox 的 tr -c 会把内容吃光，这里用 grep -ao 直接抠 .modinfo
ko_vermagic() {
	grep -ao 'vermagic=[^ ]*' "$1" 2>/dev/null | sed -n 's/^vermagic=//p' | head -1
}

echo "=== 0. 模块与当前内核是否匹配 ==="
KREL=$(uname -r)
echo "运行内核: $KREL"
for kf in "$ZKO" "$LKO"; do
	vm=$(ko_vermagic "$kf")
	case "$vm" in
		"$KREL "*) echo "OK   ${kf##*/}: vermagic 匹配" ;;
		"") echo "FAIL ${kf##*/}: 读不到 vermagic" ;;
		*) echo "FAIL ${kf##*/}: vermagic=$vm 与运行内核不一致，insmod 会被拒绝" ;;
	esac
done

echo
echo "=== 1. 加载状态 ==="
ALGO=$(cat "$BASE/zram_algo" 2>/dev/null)
[ -n "$ALGO" ] || ALGO=unknown
echo "zram_algo: $ALGO"
if module_is_loaded '^zstd(_|-)?upgrade '; then echo "zstd module: loaded"; else echo "zstd module: not loaded"; fi
if module_is_loaded '^lz4(_|-)?upgrade '; then echo "lz4 module: loaded"; else echo "lz4 module: not loaded"; fi
grep -m1 -a "1.5.7" "$ZKO" >/dev/null 2>&1 && echo "zstd ko 内嵌版本: 1.5.7"
grep -m1 -a "1.10.0" "$LKO" >/dev/null 2>&1 && echo "lz4 ko 内嵌版本: 1.10.0"

echo
echo "=== 1b. 第 2 项（新驱动）是否启用 ==="
ZRAM_ON=no
if [ -f "$BASE/enable_zram" ] || [ -f "$BASE/enable_zstd" ]; then
	ZRAM_ON=yes
fi
echo "enable_zram: $ZRAM_ON"

if [ "$ZRAM_ON" != yes ]; then
	echo
	echo "第 2 项选的是「跳过」：按设计不加载新驱动、不覆盖 perfinit、不动 zram0。"
	echo "因此下面这些检查不适用，只做只读汇报："
	echo "zram0: $(cat /sys/block/zram0/comp_algorithm 2>/dev/null)"
	echo "系统自带模块加载情况：$(grep -cE '^(binder_prio|kshrink_slabd) ' /proc/modules) 个已加载"
	echo "日志：$BASE/service.log"
	exit 0
fi

echo
echo "=== 2. crypto 注册情况（内置驱动 priority 均为 0，新驱动应为 100）==="
if [ "$ALGO" = default ]; then
	echo "第 3 项选的是「不改算法」：新驱动仍应已加载，只是 zram0 不动"
fi
for pair in "$ZDRIVER:zstd" "$LDRIVER:lz4"; do
	driver=${pair%%:*}
	algo=${pair##*:}
	if driver_block "$driver" | grep -q "driver[[:space:]]*: $driver"; then
		echo "crypto driver $algo: present ($driver)"
		driver_block "$driver"
	else
		echo "crypto driver $algo: MISSING ($driver)"
		pass=0
	fi
done

echo
echo "=== 3. 临时 zram 的引用计数实证 ==="
if [ ! -r "$CTRL/hot_add" ]; then
	echo "zram-control hot_add 不可用，跳过实证"
	exit 0
fi
before_z=$(refcnt_of "$ZDRIVER")
before_l=$(refcnt_of "$LDRIVER")
zram_no=$(cat "$CTRL/hot_add")
case "$zram_no" in
	''|*[!0-9]*|0)
		echo "hot_add 返回了非法 id: $zram_no"
		exit 1
		;;
esac
dev=/sys/block/zram$zram_no

echo "--- zstd test ---"
if echo zstd > "$dev/comp_algorithm" 2>/dev/null; then
	echo 16M > "$dev/disksize" 2>/dev/null
	after_z=$(refcnt_of "$ZDRIVER")
	echo "refcnt before: ${before_z:-unknown}, after: ${after_z:-unknown}"
	if [ -n "$after_z" ] && [ -n "$before_z" ] && [ "$after_z" -gt "$before_z" ]; then
		echo "proof: PASS (zstd 请求命中 $ZDRIVER)"
	else
		echo "proof: FAIL (refcnt 未增加，实际用的是内置旧版)"
		pass=0
	fi
else
	echo "proof: FAIL (无法在 zram$zram_no 上选择 zstd)"
	pass=0
fi
echo 1 > "$dev/reset" 2>/dev/null

echo "--- lz4 test ---"
if echo lz4 > "$dev/comp_algorithm" 2>/dev/null; then
	echo 16M > "$dev/disksize" 2>/dev/null
	after_l=$(refcnt_of "$LDRIVER")
	echo "refcnt before: ${before_l:-unknown}, after: ${after_l:-unknown}"
	if [ -n "$after_l" ] && [ -n "$before_l" ] && [ "$after_l" -gt "$before_l" ]; then
		echo "proof: PASS (lz4 请求命中 $LDRIVER)"
	else
		echo "proof: FAIL (refcnt 未增加，实际用的是内置旧版)"
		pass=0
	fi
else
	echo "proof: FAIL (无法在 zram$zram_no 上选择 lz4)"
	pass=0
fi
echo 1 > "$dev/reset" 2>/dev/null
echo "$zram_no" > "$CTRL/hot_remove" 2>/dev/null
echo "临时 zram$zram_no 已移除"

echo
echo "=== 4. perfinit.conf 覆盖 ==="
if [ "$ALGO" = default ]; then
	echo "第 3 项选了不改算法：不覆盖 perfinit.conf 是预期行为"
	echo "zram0: $(cat /sys/block/zram0/comp_algorithm 2>/dev/null)"
	echo "page-cluster: $(cat /proc/sys/vm/page-cluster 2>/dev/null)"
elif grep -q '"comp_algo"' /system_ext/etc/perfinit.conf 2>/dev/null; then
	echo "perfinit.conf: comp_algo 已生效"
	grep -E '"comp_algo"|"page_cluster"' /system_ext/etc/perfinit.conf
else
	echo "perfinit.conf: 未找到 comp_algo（bind mount 未生效，zram0 由 service.sh 切换）"
fi

echo
echo "=== 5. zram0 状态 ==="
sh "$MODDIR/zram-algo.sh" status
case "$ALGO" in
	lz4|zstd)
		if grep -q "\[$ALGO\]" /sys/block/zram0/comp_algorithm 2>/dev/null; then
			echo "zram0 current algo: $ALGO (PASS)"
		else
			echo "zram0 current algo: NOT $ALGO (FAIL)"
			pass=0
		fi
		;;
	default)
		echo "第 3 项选了不改算法，zram0 用系统默认即为正确状态（不判定 FAIL）"
		;;
esac

echo
if [ "$pass" = 1 ]; then
	echo "总判定: PASS"
else
	echo "总判定: FAIL（见上面 FAIL 行）"
fi
[ "$pass" = 1 ]
