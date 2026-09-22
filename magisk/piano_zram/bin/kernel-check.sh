#!/system/bin/sh
# 本模块唯一的限制：运行内核必须与本包 .ko 编译时的 vermagic 完全一致。
#
# 期望值不写死在脚本里，而是现场从包内 bin/zstd-upgrade.ko 的 .modinfo 读，
# 这样“脚本说的内核”和“二进制真正要求的那个内核”永远不会各说各话。
#
# 输出全部按窄行排（每行 <=26 列），因为刷入界面不换行、要横滑很难受。
#
# 用法：
#   KC_KO="$MODDIR/bin/zstd-upgrade.ko"
#   . "$MODDIR/bin/kernel-check.sh"
#   msg=$(kc_check) || { 逐行打印 "$msg"; 中止; }

# 从 .ko 里读 vermagic 的内核名部分。
# 注意：不能用 `tr -c '[:print:]' '\n'`——Android 的 toybox tr 会把内容
# 全压成换行（真机实测），正确包也会被误拦。toybox/GNU grep 都支持 -a -o。
kc_ko_vermagic() {
	grep -ao 'vermagic=[^ ]*' "$1" 2>/dev/null | sed -n 's/^vermagic=//p' | head -1
}

# 把长字符串按 26 列断行打印（前面留一空格缩进）
kc_wrap() {
	local s="$1" n=0
	s="$1"
	while [ -n "$s" ] && [ "$n" -lt 8 ]; do
		echo " ${s}" | cut -c1-26
		s=$(echo "$s" | cut -c27-999)
		n=$((n + 1))
	done
}

kc_check() {
	local now exp
	now=$(uname -r 2>/dev/null)

	if [ -z "$now" ]; then
		echo "读不到 uname -r"
		echo "刷入环境不完整"
		echo "（Magisk 未装或"
		echo " recovery 不可用）"
		echo "请先装好 Magisk，"
		echo "再用 magisk --install-module"
		echo "或带 Magisk 的卡刷刷入"
		return 1
	fi

	if [ ! -r "$KC_KO" ]; then
		echo "包内没有可读的"
		echo " bin/zstd-upgrade.ko"
		echo "安装包不完整：zip 被截断"
		echo "或解压出错。请对照"
		echo " release/SHA256SUMS.txt"
		echo "校验 sha256 后重新推送。"
		echo "当前内核:"
		kc_wrap "$now"
		return 1
	fi

	exp=$(kc_ko_vermagic "$KC_KO")
	if [ -z "$exp" ]; then
		echo ".ko 里读不到 vermagic"
		echo "该文件已损坏或不属于本模块"
		echo "请校验 sha256 后重装"
		return 1
	fi

	if [ "$now" != "$exp" ]; then
		echo "内核不匹配"
		echo " 本包适配:"
		kc_wrap "$exp"
		echo " 当前内核:"
		kc_wrap "$now"
		echo "两个 .ko 的 vermagic 与"
		echo "符号 CRC 都写死了，内核"
		echo "一换 insmod 必被内核拒绝"
		echo "(-ENOEXEC)，装了等于没装"
		echo "所以这里主动中止，不留"
		echo "一个只会静默失败的模块。"
		echo ""
		echo "办法1: 按当前内核重编"
		echo " sh build/BUILD-6.6.118.sh"
		echo "（改 VERMAGIC 与 headers）"
		echo "办法2: 刷回适配本包的 ROM"
		echo ""
		echo "本模块到此为止，不做任何"
		echo "改动；系统保持原样。"
		return 1
	fi

	return 0
}
