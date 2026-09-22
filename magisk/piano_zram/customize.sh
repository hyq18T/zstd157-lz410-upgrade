#!/system/bin/sh

SKIPMOUNT=true
PROPFILE=false
POSTFSDATA=true
LATESTARTSERVICE=true

PICK_TIMEOUT=20
KEY_UP_PAT='(KEY_VOLUMEUP|KEY_UP)'
KEY_DOWN_PAT='(KEY_VOLUMEDOWN|KEY_DOWN)'

print_modname() {
	ui_print "====================="
	ui_print " MI Piano 调优"
	ui_print " + zram 算法升级"
	ui_print "====================="
}

# ---------- 音量键：上=切换 下=确认 超时=当前项 ----------

key_begin() {
	KEYEVF="$TMPDIR/.piano_zram_keys"
	rm -f "$KEYEVF"
	getevent -l >"$KEYEVF" 2>/dev/null &
	KEYPID=$!
}

key_end() {
	[ -n "$KEYPID" ] && kill "$KEYPID" 2>/dev/null
	KEYPID=""
	[ -n "$KEYEVF" ] && rm -f "$KEYEVF"
}

key_count() {
	local n
	[ -f "$KEYEVF" ] || { echo 0; return; }
	n=$(grep -cE "$1[[:space:]]+DOWN" "$KEYEVF" 2>/dev/null)
	[ -n "$n" ] || n=0
	echo "$n"
}

pick_show() {
	local i lbl mark
	for i in 1 2 3 4 5; do
		[ "$i" -gt "$PICK_N" ] && break
		eval "lbl=\$PICK_OPT_$i"
		mark="  "
		[ "$i" = "$1" ] && mark=">"
		ui_print " ${mark}${i}.${lbl}"
	done
}

# 结果写入 PICKED（1-based）
pick_option() {
	local o cur=1 up dn nu nd adv t=1

	PICK_N=0
	for o in "$@"; do
		PICK_N=$((PICK_N + 1))
		eval "PICK_OPT_$PICK_N=\"\$o\""
	done

	if [ "$PICK_KEYS_OK" != 1 ]; then
		PICKED=1
		eval "o=\$PICK_OPT_1"
		ui_print " ! 无getevent 用:$o"
		return 0
	fi

	pick_show 1
	ui_print " 上:切换 下:确认"
	ui_print " ${PICK_TIMEOUT}秒未按=当前项"

	key_begin
	up=$(key_count "$KEY_UP_PAT")
	dn=$(key_count "$KEY_DOWN_PAT")

	while [ "$t" -le "$PICK_TIMEOUT" ]; do
		nu=$(key_count "$KEY_UP_PAT")
		if [ "$nu" -gt "$up" ]; then
			adv=$((nu - up))
			up=$nu
			cur=$(((cur - 1 + adv) % PICK_N + 1))
			pick_show "$cur"
		fi
		nd=$(key_count "$KEY_DOWN_PAT")
		if [ "$nd" -gt "$dn" ]; then
			dn=$nd
			PICKED=$cur
			key_end
			eval "o=\$PICK_OPT_$PICKED"
			ui_print " => $o"
			return 0
		fi
		sleep "$PICK_SLEEP"
		t=$((t + 1))
	done

	PICKED=$cur
	key_end
	eval "o=\$PICK_OPT_$PICKED"
	ui_print " 未按 用:$o"
	return 0
}

# ---------- 安装 ----------

# 唯一限制：内核必须与包内 .ko 一致
kernel_gate() {
	local kmsg
	KC_KO="$MODPATH/bin/zstd-upgrade.ko"
	if [ ! -f "$MODPATH/bin/kernel-check.sh" ]; then
		ui_print " × 包不完整"
		ui_print "   缺 kernel-check.sh"
		ui_print "   请校验 sha256 后重推再刷"
		gate_abort
	fi
	. "$MODPATH/bin/kernel-check.sh"
	if ! kmsg=$(kc_check 2>&1); then
		ui_print ""
		ui_print "====================="
		ui_print " 安装中止：内核限制"
		ui_print "====================="
		echo "$kmsg" | while IFS= read -r kl; do
			[ -n "$kl" ] && ui_print " $kl"
		done
		gate_abort
	fi
	ui_print " 内核校验通过"
	return 0
}

gate_abort() {
	if command -v abort >/dev/null 2>&1; then
		abort "piano_zram：内核不匹配，已中止"
	fi
	exit 1
}

on_install() {
	[ -f "$TMPDIR/.piano_zram_install_done" ] && return 0

	kernel_gate

	# “系统默认”取内核编译期的 CONFIG_ZRAM_DEF_COMP（固定值），
	# 不能用 zram0 当前算法 —— 那可能正是上一次安装改过的结果
	DEF_ALGO=$(zcat /proc/config.gz 2>/dev/null | sed -n 's/^CONFIG_ZRAM_DEF_COMP=//p' | tr -d '"')
	[ -n "$DEF_ALGO" ] || DEF_ALGO=lzo-rle
	CUR_ALGO=$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' /sys/block/zram0/comp_algorithm 2>/dev/null)
	[ -n "$CUR_ALGO" ] || CUR_ALGO=未知

	ui_print ""
	ui_print "[1/3] MI Piano 调优"
	ui_print " VM/IO/F2FS 参数调优"
	pick_option " 启用" " 跳过"
	[ "$PICKED" = 1 ] && touch "$MODPATH/enable_piano"

	ui_print ""
	ui_print "[2/3] 新驱动"
	ui_print " zstd 1.5.7 + lz4 1.10.0"
	ui_print " 注册高优先级 crypto 驱动"
	pick_option " 启用" " 跳过"
	[ "$PICKED" = 1 ] && touch "$MODPATH/enable_zram"

	DESC=""
	[ -f "$MODPATH/enable_piano" ] && DESC="MI Piano 调优"

	if [ -f "$MODPATH/enable_zram" ]; then
		ui_print ""
		ui_print "[3/3] zram0 用哪个算法"
		ui_print " 只决定 zram0 算法；"
		ui_print " 新驱动照上面选择加载"
		ui_print " 系统默认:$DEF_ALGO"
		ui_print " 当前显示:$CUR_ALGO"
		pick_option " lz4" " zstd" " 不改(回/留$DEF_ALGO)"
		case "$PICKED" in
			1) ALGO=lz4 ;;
			2) ALGO=zstd ;;
			*) ALGO=default ;;
		esac
		echo "$ALGO" > "$MODPATH/zram_algo"
		if [ "$ALGO" = default ]; then
			rm -rf "$MODPATH/system_ext"
			DESC="$DESC + 新驱动(已载) zram0不改"
		else
			sed -i "s/\"comp_algo\": \"[^\"]*\"/\"comp_algo\": \"$ALGO\"/" "$MODPATH/system_ext/etc/perfinit.conf"
			DESC="$DESC + 新驱动 zram0=$ALGO"
		fi
	else
		echo default > "$MODPATH/zram_algo"
		rm -rf "$MODPATH/system_ext"
		if [ -n "$DESC" ]; then
			DESC="$DESC（未启用新驱动）"
		else
			DESC="未启用任何功能"
		fi
	fi
	sed -i "s|^description=.*|description=$DESC|" "$MODPATH/module.prop"

	ui_print ""
	ui_print "- 完成 重启生效"
	ui_print "- 错过按键可手改:"
	ui_print "  .../piano_zram/zram_algo"
	ui_print "  值 lz4|zstd|default"
	touch "$TMPDIR/.piano_zram_install_done"
}

set_permissions() {
	set_perm_recursive "$MODPATH" 0 0 0755 0644
	for f in "$MODPATH"/*.sh "$MODPATH"/bin/*.sh; do
		[ -f "$f" ] && set_perm "$f" 0 0 0755
	done
}

PICK_SLEEP=1
sleep 0.2 2>/dev/null || PICK_SLEEP=1
if command -v getevent >/dev/null 2>&1; then
	PICK_KEYS_OK=1
else
	PICK_KEYS_OK=0
fi

if [ ! -f "$TMPDIR/.piano_zram_install_done" ]; then
	on_install
fi

if [ ! -f "$MODPATH/enable_zram" ]; then
	rm -rf "$MODPATH/system_ext"
fi
set_permissions
