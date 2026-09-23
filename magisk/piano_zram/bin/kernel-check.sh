#!/system/bin/sh
# 本模块唯一的限制：内核大版本必须与本包 .ko 编译时的那个一致。
#
# 校验粒度：只比 uname -r 的开头版本号（比如 6.6.118），不比后面那串构建号。
# 前缀不同 -> 拦下（这个 .ko 根本不是给这个内核编的）。
# 前缀相同、完整 vermagic 不同 -> 放行，但打印警告：最终能不能加载由内核说了算
# （本内核 CONFIG_MODULE_FORCE_LOAD 未开，构建号差太多时 insmod 仍会被拒），
# 加载失败时 zram-algo.sh 会按 refcnt 判据发现"新驱动没在服务"，不会假装成功。
#
# 期望值不写死在脚本里，而是现场从包内 bin/zstd-upgrade.ko 的 .modinfo 读，
# 保证"脚本声称的内核"和"二进制真正要求的那个内核"不会各说各话。
#
# 用法：
#   KC_KO="$MODDIR/bin/zstd-upgrade.ko"
#   . "$MODDIR/bin/kernel-check.sh"
#   KC_MSG=$(kc_check 2>&1); rc=$?
#   # 有输出就逐行打印；rc=1 才中止
# 输出全部按窄行排（<=26 列），刷入界面不用左右滑。

# 从 .ko 里读 vermagic。注意：Android toybox 的 `tr -c '[:print:]' '\n'` 会把内容
# 全压成换行（真机实测），所以用 grep -ao 直接抠 .modinfo 里那一条。
kc_ko_vermagic() {
	grep -ao 'vermagic=[^ ]*' "$1" 2>/dev/null | sed -n 's/^vermagic=//p' | head -1
}

# 取内核名的开头版本段：6.6.118-android15-8-gxxxx-4k -> 6.6.118
kc_prefix() {
	echo "$1" | cut -d'-' -f1
}

# 长字符串按 26 列断行打印
kc_wrap() {
	local s="$1" n=0
	while [ -n "$s" ] && [ "$n" -lt 8 ]; do
		echo " ${s}" | cut -c1-26
		s=$(echo "$s" | cut -c27-999)
		n=$((n + 1))
	done
}

kc_check() {
	local now exp nowp expp
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

	nowp=$(kc_prefix "$now")
	expp=$(kc_prefix "$exp")

	if [ "$nowp" != "$expp" ]; then
		echo "内核版本不匹配"
		echo " 本包适配 : $expp"
		echo " 当前内核 : $nowp"
		echo "完整串："
		kc_wrap "$exp"
		kc_wrap "$now"
		echo ".ko 的 vermagic 与符号 CRC"
		echo "都按这个内核编译，换内核"
		echo "insmod 必被内核拒绝"
		echo "(-ENOEXEC)，装了等于没装，"
		echo "所以这里主动中止。"
		echo ""
		echo "办法1: 按当前内核重编"
		echo " sh build/BUILD-*.sh"
		echo "（改 VERMAGIC 与 headers）"
		echo "办法2: 用适配当前内核的包"
		echo ""
		echo "本模块到此为止，不做任何"
		echo "改动；系统保持原样。"
		return 1
	fi

	if [ "$now" != "$exp" ]; then
		echo " ! 内核版本 $nowp 匹配，但构建号不同："
		kc_wrap "   .ko: $exp"
		kc_wrap "   运行: $now"
		echo "   照常加载，能否 insmod 由内核决定；"
		echo "   失败会在 service.log 写明，zram0 不受影响。" >&2
	fi

	return 0
}
