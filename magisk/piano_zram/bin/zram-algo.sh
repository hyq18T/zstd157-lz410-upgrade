#!/system/bin/sh
# zram0 压缩算法切换（lz4 / zstd / default=保持系统原样）+ page-cluster

MODDIR=${0%/*}
BASE=${MODDIR%/bin}
ZRAM_DIR=/sys/block/zram0
ZRAM_DEV=/dev/block/zram0
PAGE_CLUSTER=0
DEFAULT_SIZE=17179869184

ALGO=$(cat "$BASE/zram_algo" 2>/dev/null)
case "$ALGO" in
	lz4|zstd|default) ;;
	*) ALGO=lz4 ;;
esac
case "$2" in
	lz4|zstd|default) ALGO=$2 ;;
esac

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

current_algo() {
	sed -n 's/.*\[\([^]]*\)\].*/\1/p' "$ZRAM_DIR/comp_algorithm" 2>/dev/null
}

# 新驱动是不是真的在服务 zram0：只看 /proc/crypto 里它的 refcnt。
# 内置 zstd-generic 在 8 核机上服务 zram0 时 refcnt=9（每 CPU 一条流 +1），
# 而我们注册的 zstd-new-generic 只要没被用，refcnt 恒为 1。
new_driver_refcnt() {
	local drv
	case "$1" in
		lz4) drv=lz4-new-generic ;;
		zstd) drv=zstd-new-generic ;;
		*) echo ""; return 1 ;;
	esac
	awk -v d="$drv" 'BEGIN { RS=""; ORS="\n" }
		$0 ~ d {
			n = split($0, L, "\n")
			for (i = 1; i <= n; i++)
				if (L[i] ~ /refcnt/) {
					split(L[i], A, ":")
					gsub(/[^0-9]/, "", A[2])
					print A[2]
					exit
				}
		}' /proc/crypto 2>/dev/null
}

swap_active() {
	grep -qw "$ZRAM_DEV" /proc/swaps 2>/dev/null
}

set_page_cluster() {
	if [ -w /proc/sys/vm/page-cluster ]; then
		echo "$PAGE_CLUSTER" > /proc/sys/vm/page-cluster 2>/dev/null && log "page-cluster -> $PAGE_CLUSTER"
	else
		log "page-cluster: 不可写"
	fi
}

# 切到 lz4/zstd 前确保对应新驱动已注册，否则会静默退回内置旧版
ensure_driver() {
	case "$ALGO" in
		lz4) drv=lz4-new-generic ;;
		zstd) drv=zstd-new-generic ;;
		*) return 0 ;;
	esac
	if grep -q "driver[[:space:]]*: $drv" /proc/crypto 2>/dev/null; then
		return 0
	fi
	log "驱动 $drv 未注册，先加载"
	sh "$MODDIR/zstd-upgrade.sh" load
	if grep -q "driver[[:space:]]*: $drv" /proc/crypto 2>/dev/null; then
		log "驱动 $drv 加载成功"
		return 0
	fi
	log "警告：$drv 仍不可用，zram0 将使用内置旧版算法"
	return 1
}

reconfigure() {
	local i orig_size

	if swap_active; then
		i=0
		while swap_active && [ "$i" -lt 5 ]; do
			swapoff "$ZRAM_DEV" 2>/dev/null
			i=$((i + 1))
			[ "$i" -lt 5 ] && sleep 2
		done
	fi
	if swap_active; then
		log "swapoff 失败，跳过 zram0 重建"
		return 1
	fi

	orig_size=$(cat "$ZRAM_DIR/disksize" 2>/dev/null)
	case "$orig_size" in
		''|*[!0-9]*|0) orig_size=$DEFAULT_SIZE ;;
	esac

	if ! echo 1 > "$ZRAM_DIR/reset" 2>/dev/null; then
		log "zram0 reset 失败"
		return 1
	fi
	if ! echo "$ALGO" > "$ZRAM_DIR/comp_algorithm" 2>/dev/null; then
		log "comp_algorithm=$ALGO 写入失败"
		return 1
	fi
	log "comp_algorithm -> $ALGO"

	if ! echo "$orig_size" > "$ZRAM_DIR/disksize" 2>/dev/null; then
		log "disksize=$orig_size 写入失败"
		return 1
	fi
	log "disksize -> $orig_size"

	if ! mkswap "$ZRAM_DEV" >/dev/null 2>&1; then
		log "mkswap 失败"
		return 1
	fi
	if ! swapon "$ZRAM_DEV" 2>/dev/null; then
		log "swapon 失败"
		return 1
	fi
	log "swapon ok"
	return 0
}

case "$1" in
	apply)
		if [ "$ALGO" = default ]; then
			log "选择的是保持系统默认，page-cluster 与 zram0 算法都不改动"
			exit 0
		fi
		set_page_cluster
		if [ ! -e "$ZRAM_DIR/comp_algorithm" ]; then
			log "zram0 未就绪"
			exit 1
		fi
		case "$ALGO" in
			lz4) NEED=lz4-new-generic ;;
			zstd) NEED=zstd-new-generic ;;
			*) NEED="" ;;
		esac
		ensure_driver
		log "目标算法：$ALGO"

		cur=$(current_algo)
		r=$(new_driver_refcnt "$ALGO")
		if [ "$cur" = "$ALGO" ] && [ -n "$r" ] && [ "$r" -gt 1 ]; then
			log "zram0 已是 $ALGO 且由 $NEED 在服务（refcnt=$r），无需重建"
			exit 0
		fi
		if [ "$cur" = "$ALGO" ]; then
			log "注意：zram0 显示 $ALGO 但 $NEED 的 refcnt=${r:-无法读取}，"
			log "      说明现在压页的是内置旧版驱动，必须重建 zram0 才会用上新驱动"
		fi
		reconfigure
		rc=$?

		r2=$(new_driver_refcnt "$ALGO")
		if [ "$rc" = 0 ] && [ -n "$r2" ] && [ "$r2" -gt 1 ]; then
			log "重建完成，$NEED 已在服务 zram0（refcnt=$r2）"
		elif [ "$rc" = 0 ]; then
			log "重建已完成，但 $NEED 的 refcnt=${r2:-无法读取}，新驱动可能未被用上，请看 verify.sh"
		fi
		exit "$rc"
		;;
	status)
		echo "selected algo: $ALGO"
		echo "comp_algorithm: $(cat "$ZRAM_DIR/comp_algorithm" 2>/dev/null)"
		echo "page-cluster: $(cat /proc/sys/vm/page-cluster 2>/dev/null)"
		if swap_active; then
			awk '$2=="partition" && $1 ~ /zram0/ { printf "zram0 swap: size=%d used=%d priority=%s\n", $3, $4, $5 }' /proc/swaps
		else
			echo "zram0: not in /proc/swaps"
		fi
		;;
	*)
		echo "usage: sh ${0##*/} apply [lz4|zstd|default]|status"
		exit 1
		;;
esac
