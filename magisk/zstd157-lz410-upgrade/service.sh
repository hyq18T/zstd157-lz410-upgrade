#!/system/bin/sh
MODDIR=${0%/*}
[ -f "$MODDIR/auto_load" ] || exit 0
sh "$MODDIR/zstd-upgrade.sh" load
