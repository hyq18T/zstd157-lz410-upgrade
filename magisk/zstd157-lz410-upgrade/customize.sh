#!/system/bin/sh
ui_print "- zstd 1.5.7 + lz4 1.10.0 压缩算法升级模块已安装"
ui_print "- 已包含 auto_load，重启后自动加载 zstd-upgrade.ko 和 lz4-upgrade.ko"
ui_print "- 手动加载: adb shell su -c 'sh /data/adb/modules/zstd-upgrade/load.sh'"
ui_print "- 版本验证: adb shell su -c 'sh /data/adb/modules/zstd-upgrade/verify.sh'"
ui_print "- 停用自动加载: rm -f /data/adb/modules/zstd-upgrade/auto_load"
