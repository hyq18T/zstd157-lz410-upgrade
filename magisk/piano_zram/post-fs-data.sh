#!/system/bin/sh
# 只在选了 lz4/zstd 时把自定义 perfinit.conf bind 到 /system_ext，让 Perfinit 开机就按所选算法初始化 zram0。
# 选择“保持默认”时不做任何覆盖。

MODDIR=${0%/*}
SRC="$MODDIR/system_ext/etc/perfinit.conf"
DST=/system_ext/etc/perfinit.conf
LOG="$MODDIR/post-fs-data.log"

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

{ [ -f "$MODDIR/enable_zram" ] || [ -f "$MODDIR/enable_zstd" ]; } || exit 0

# 与 service.sh 同一个限制：内核不匹配就什么都不做
KC_KO="$MODDIR/bin/zstd-upgrade.ko"
if [ -f "$MODDIR/bin/kernel-check.sh" ]; then
	. "$MODDIR/bin/kernel-check.sh"
	if ! KMSG=$(kc_check 2>&1); then
		log "== 本模块唯一的限制未通过（内核与本包 .ko 不一致），跳过 perfinit 覆盖 =="
		echo "$KMSG" | while IFS= read -r kl; do
			[ -n "$kl" ] && log "$kl"
		done
		exit 0
	fi
	log "内核校验通过：$(uname -r)"
else
	log "缺少 bin/kernel-check.sh，跳过 perfinit 覆盖"
	exit 0
fi

# 早在这里就把两个新驱动注册上：Perfinit 是在 post-fs-data 之后才创建 zram0 的，
# 抢在它前面注册，zram0 第一次建起来就直接命中新驱动，不需要事后 swap 重建。
# （万一还是晚于 zram0 创建，service.sh 里的 zram-algo.sh 会按 refcnt 判断并强制重建）
log "== 注册 zstd/lz4 新驱动 =="
sh "$MODDIR/bin/zstd-upgrade.sh" load >>"$LOG" 2>&1

ALGO=$(cat "$MODDIR/zram_algo" 2>/dev/null)
case "$ALGO" in
	lz4|zstd) ;;
	*) log "第 3 项选了不改算法：驱动已注册，zram0 与 perfinit.conf 都不改动"; exit 0 ;;
esac

[ -f "$SRC" ] || exit 0
[ -f "$DST" ] || exit 0

chcon u:object_r:system_file:s0 "$SRC" 2>/dev/null

if mount -o bind "$SRC" "$DST" 2>/dev/null; then
	log "bind ok: $SRC -> $DST"
	exit 0
fi

mount -o bind "$SRC" "$DST" 2>>"$LOG"
log "bind retry: exit=$?"
exit 0
