#!/system/bin/sh

MODDIR=${0%/*}
LOG="$MODDIR/service.log"

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

write_val() {
	[ -w "$1" ] || return 1
	echo "$2" > "$1" 2>/dev/null
}

# 系统自带的内核模块：只在本内核没有加载它、且这份二进制确实是给当前内核编译的时候才补加载。
# /vendor/lib/modules 里存在不少上个 ROM 留下的陈旧 .ko（实测 binder_prio.ko 还是 6.6.57 的），
# 而本内核 CONFIG_MODULE_FORCE_LOAD 未开，版本不对的 insmod 一定被拒，所以先比 vermagic 再决定加载。
system_module_load() {
	local name f kv
	for name in binder_prio kshrink_slabd; do
		if grep -Eq "^${name} " /proc/modules 2>/dev/null; then
			log "$name: 系统已加载"
			continue
		fi
		f=""
		for d in /vendor/lib/modules /vendor_dlkm/lib/modules /system/lib/modules /odm/lib/modules; do
			[ -f "$d/$name.ko" ] && f="$d/$name.ko" && break
		done
		if [ -z "$f" ]; then
			log "$name: 系统中没有该模块，跳过"
			continue
		fi
		kv=$(kc_ko_vermagic "$f")
		if [ "$kv" != "$(uname -r)" ]; then
			log "$name: $f 是内核 $kv 的陈旧副本（当前 $(uname -r)），加载会被拒绝，跳过"
			continue
		fi
		if insmod "$f" 2>>"$LOG"; then
			log "$name: 已补加载 $f"
		else
			log "$name: insmod $f 失败"
		fi
	done
}

load_piano() {
	log "== MI Piano 系统调优 =="
	system_module_load

	if [ ! -e /dev/ntsync ] && [ -d /sys/class/misc/ntsync ]; then
		dev=$(cat /sys/class/misc/ntsync/dev 2>/dev/null)
		if [ -n "$dev" ]; then
			major=${dev%%:*}
			minor=${dev##*:}
			if mknod /dev/ntsync c "$major" "$minor" 2>>"$LOG"; then
				chmod 0666 /dev/ntsync
				chcon u:object_r:ntsync_device:s0 /dev/ntsync 2>/dev/null
				log "ntsync device: /dev/ntsync ($dev)"
			else
				log "ntsync device: mknod 失败"
			fi
		fi
	fi

	write_val /proc/sys/vm/extfrag_threshold 800
	write_val /proc/sys/vm/compact_unevictable_allowed 0
	write_val /proc/sys/vm/oom_dump_tasks 0

	for dir in /sys/block/*/queue/iosched; do
		[ -d "$dir" ] || continue
		write_val "$dir/read_expire" 4
		write_val "$dir/write_expire" 8
		write_val "$dir/async_depth" 126
		write_val "$dir/prio_aging_expire" 200
		write_val "$dir/io_threshold" 256
	done

	for dir in /sys/fs/f2fs/*; do
		[ -d "$dir" ] || continue
		write_val "$dir/ckpt_thread_ioprio" "rt,3"
	done
	log "Piano 调优流程结束"
}

load_drivers() {
	log "== 加载压缩算法升级驱动（第 2 项已启用）=="
	sh "$MODDIR/bin/zstd-upgrade.sh" load >>"$LOG" 2>&1
	log "驱动加载流程结束"
}

switch_zram() {
	waited=0
	while [ "$waited" -lt 120 ]; do
		if [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ]; then
			log "sys.boot_completed=1 (after ${waited}s)"
			break
		fi
		sleep 2
		waited=$((waited + 2))
	done
	if [ "$waited" -ge 120 ]; then
		log "sys.boot_completed 等待超时"
	fi

	log "等待 15 秒，避开 Perfinit 开机重建"
	sleep 15

	log "== zram0 切换 $ALGO（仅执行一次）=="
	sh "$MODDIR/bin/zram-algo.sh" apply >>"$LOG" 2>&1
	if grep -q "\[$ALGO\]" /sys/block/zram0/comp_algorithm 2>/dev/null; then
		log "zram0 $ALGO 切换完成"
	else
		log "zram0 $ALGO 切换未生效，本次开机不再重复执行"
	fi
	log "zram0 切换流程结束"
}

: > "$LOG"

# 本模块唯一的限制：内核必须与包内 .ko 匹配。刷完系统/换内核后这里会挡住，
# 避免留下一个只会每开机静默失败的模块。
KC_KO="$MODDIR/bin/zstd-upgrade.ko"
if [ -f "$MODDIR/bin/kernel-check.sh" ]; then
	. "$MODDIR/bin/kernel-check.sh"
	if ! KMSG=$(kc_check 2>&1); then
		log "== 本模块唯一的限制未通过（内核与本包 .ko 不一致），本次开机不做任何改动 =="
		echo "$KMSG" | while IFS= read -r kl; do
			[ -n "$kl" ] && log "$kl"
		done
		exit 0
	fi
	log "内核校验通过：$(uname -r)"
else
	log "缺少 bin/kernel-check.sh，安装包不完整，本次开机不做任何改动"
	exit 0
fi

ALGO=$(cat "$MODDIR/zram_algo" 2>/dev/null)
case "$ALGO" in
	lz4|zstd) ;;
	default) ALGO=default ;;
	*) ALGO=lz4 ;;
esac
log "zram 算法配置：$ALGO"

if [ -f "$MODDIR/enable_piano" ]; then
	load_piano
fi

ZRAM_ON=no
if [ -f "$MODDIR/enable_zram" ] || [ -f "$MODDIR/enable_zstd" ]; then
	ZRAM_ON=yes
fi

# 第 2 项决定要不要新驱动；第 3 项只决定 zram0 用哪个算法，两者互不牵连
if [ "$ZRAM_ON" = yes ]; then
	load_drivers
	if [ "$ALGO" = default ]; then
		log "第 3 项选了不改算法：zram0 保持系统默认，不重建、不改 page-cluster、不覆盖 perfinit.conf"
	else
		switch_zram
	fi
else
	log "第 2 项未启用：不加载新驱动，也不改动 zram0"
fi

exit 0
