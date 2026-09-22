#!/system/bin/sh
# 卸载时只回收本模块自己注册的两个驱动。
# binder_prio / kshrink_slabd 是新系统自带的模块（系统自己就会加载），不去 rmmod，
# 以免影响 MIUI/HyperOS 自身的功能。zram0 若正持有新驱动的 tfm，rmmod 会失败，
# 重启后自然回到系统默认算法。

MODDIR=${0%/*}

sh "$MODDIR/bin/zstd-upgrade.sh" unload >/dev/null 2>&1

rm -f /dev/ntsync 2>/dev/null
rm -f "$MODDIR/service.log" 2>/dev/null
rm -f "$MODDIR/post-fs-data.log" 2>/dev/null

exit 0
