# zstd 1.5.7 + lz4 1.10.0 Magisk 升级模块

机型: 小米 15 Pro (2410DPN6CC / haotian)
内核: 6.6.77-android15-8-gca30f3b4bef6-abogki440974771-4k
模块版本: v1.5.7-lz4.10.0

## 用途

模块向官方内核注册两个同名高优先级 crypto 压缩驱动：

| 算法 | 驱动名 | priority | 内嵌源码版本 |
| --- | --- | --- | --- |
| zstd | zstd-new-generic | 100 | 1.5.7 |
| lz4 | lz4-new-generic | 100 | 1.10.0 |

内置驱动的 priority 为 0，因此之后新建的 zram 压缩上下文会优先命中
本模块注册的高优先级驱动。

## 工作原理

这不是替换内核内置算法库，而是注册同名高优先级 crypto 驱动进行遮蔽：

1. 重启后由 Magisk 自动加载 zstd-upgrade.ko 和 lz4-upgrade.ko。
2. `/proc/crypto` 会出现 `zstd-new-generic` 与 `lz4-new-generic`，
   priority 均为 100。
3. zram 写入 `zstd` 或 `lz4` 时通过 crypto 查找算法，会优先命中新驱动。
4. 模块只影响之后新建的压缩上下文；已经在线的 zram0 不会自动切换。
5. 内核导出的 `ZSTD_versionString` 等符号不会改变，仍显示内核内置版本。

## 文件

module.prop: Magisk 模块信息
customize.sh: 安装提示
service.sh: 开机加载脚本，存在 auto_load 文件时执行
load.sh / unload.sh: 手动加载/卸载脚本
zstd-upgrade.sh: 双算法状态/加载/卸载脚本
verify.sh: 版本和命中验证脚本
zstd-upgrade.ko: zstd 1.5.7 内核模块 (SHA256 CB44BDED96D9C8FA8B5F42A879E9F5615A5F47F36E0317D565AFD9F4014C969C)
lz4-upgrade.ko: lz4 1.10.0 内核模块 (SHA256 D512B1E05F954B82F7B6DE6CE7B1D167E26C8185F94271DD28C5101E9A6C1934)

## 常用命令

```
adb shell su -c 'sh /data/adb/modules/zstd-upgrade/load.sh'
adb shell su -c 'sh /data/adb/modules/zstd-upgrade/zstd-upgrade.sh status'
adb shell su -c 'sh /data/adb/modules/zstd-upgrade/verify.sh'
adb shell su -c 'sh /data/adb/modules/zstd-upgrade/unload.sh'
```

verify.sh 会新建一个临时 zram 设备，依次选择 zstd 和 lz4 算法，
分别检查 `zstd-new-generic` 与 `lz4-new-generic` 的 refcnt 是否增加，
验证完成后自动移除临时设备，不会触碰 zram0，也不会修改交换配置。

## 启用开机自动加载

模块压缩包已包含 auto_load 文件，安装并重启后会自动加载。
如果之后想临时停用，删除标记即可:

```
adb shell su -c 'rm -f /data/adb/modules/zstd-upgrade/auto_load'
```

## 风险

内核模块加载属于高风险操作，可能触发重启、卡开机或变砖。
如出现异常，可在 Magisk 中关闭模块或删除 auto_load 后再重启。
真正让 Android 使用新 zstd/lz4 还需要把系统交换设备切到新建的 zram，
这属于系统级配置，风险较高，请先只做验证。
