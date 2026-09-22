# piano_zram（v1.9）—— MI Piano 系统调优 + zram 压缩算法升级

面向小米 15 Pro（`2410DPN6CC` / haotian）、内核
`6.6.118-android15-8-gc44b714366cc-abogki519650608-4k` 的 Magisk 模块。
**只认这个 vermagic**：换内核后包内的 `.ko` 会被 `insmod` 直接拒载，模块的安装期闸门也会拦下并说明原因。

本目录只放脚本。构建产物 `bin/zstd-upgrade.ko`、`bin/lz4-upgrade.ko` 需自行按
[../../README.md](../../README.md) 的“构建”一节生成后再打包。

## 目录

```text
customize.sh              安装流程：内核闸门 + 三问菜单（音量上切换 / 音量下确认）
bin/kernel-check.sh       唯一的限制：内核必须与包内 .ko 的 vermagic 一致（期望值现场从 .ko 读）
post-fs-data.sh           开机早期注册两个新驱动（赶在 Perfinit 建 zram0 之前）+ 按需 bind perfinit.conf
service.sh                系统调优；按第 3 项的选择决定是否重建 zram0（只执行一次，不轮询）
bin/zstd-upgrade.sh       手动 load / unload / status 两个驱动
bin/zram-algo.sh          zram0 算法切换：apply [lz4|zstd|default] | status
bin/verify.sh             验证：.ko 与运行内核是否匹配 → 注册 → refcnt 实证 → 覆盖与 zram0 现状
module.prop uninstall.sh
system_ext/etc/perfinit.conf   基于当前系统同路径文件改写（page_cluster=0、comp_algo 由安装时决定）
```

## 三个菜单各管一件事

1. **MI Piano 系统调优**：VM/IO/F2FS 参数；`binder_prio`、`kshrink_slabd` 若系统未加载且
   系统自带的 `.ko` 确实是当前内核编译的，才补加载（模块不再捆绑任何陈旧 `.ko`）。
2. **装不装新驱动**：`zstd-upgrade.ko` + `lz4-upgrade.ko` 注不注册。
3. **zram0 用哪个算法**：`lz4` / `zstd` / `不改(回/留系统默认)`。系统默认取
   `CONFIG_ZRAM_DEF_COMP`（本机 `lzo-rle`），不取 zram0 当前值——那可能正是上一次安装改出来的。

选“不改”时新驱动照第 2 项注册、只是 zram0 不动：不覆盖 `perfinit.conf`、不重建、不改 `page-cluster`。

## 安装

```sh
adb push piano_zram_v1.9.zip /data/local/tmp/
adb shell su -c 'magisk --install-module /data/local/tmp/piano_zram_v1.9.zip'
adb reboot
```

包内无 `META-INF`，只能走 Magisk（管理器或 `magisk --install-module`）；recovery 直刷需自行补
`update-binary`。错过按键不要紧：超时按当前高亮项，且重启前可手改

```sh
echo 'lz4|zstd|default' > /data/adb/modules_update/piano_zram/zram_algo
touch|rm -f /data/adb/modules_update/piano_zram/enable_piano|enable_zram
```

## 验证

```sh
adb shell su -c 'sh /data/adb/modules/piano_zram/bin/verify.sh'
```

判断新驱动是否真的在服务 zram0，只看 refcnt（8 核机上约 9 才是在用，1 是空载）：

```sh
grep -A5 "zstd-new-generic" /proc/crypto | grep refcnt
grep -A5 "zstd-generic"     /proc/crypto | grep refcnt
```

`zram-algo.sh` 也按这个判据决定是否强制重建 zram0，不再只看算法名是否相等。

## 回退

```sh
echo default > /data/adb/modules/piano_zram/zram_algo && reboot   # 只退算法
# 或在 Magisk 里停用/卸载本模块后重启
```

卸载只回收本模块注册的两个驱动，不会 `rmmod` 系统自带的 `binder_prio`/`kshrink_slabd`；
若 zram0 正持有新驱动的 tfm，`rmmod` 会失败，重启后自然回到系统默认。

## 风险

内核模块加载属高风险操作；新驱动是全局遮蔽（所有按 `cra_name` 查找 `zstd`/`lz4` 的使用方都会命中）；
zstd 侧硬编码 level 3、每个 tfm 会 `vmalloc` 一整套上下文；内嵌 lz4 输出不带长度头，与内置产物不互通；
zram0 切换中途失败会留一个本次开机没有交换的状态。详细说明见仓库根 README 的“风险”。
