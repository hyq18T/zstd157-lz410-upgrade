# zstd 1.5.7 + lz4 1.10.0 内核压缩算法升级模块（源码）

面向小米 15 Pro（haotian / 2410DPN6CC，内核
`6.6.77-android15-8-gca30f3b4bef6-abogki440974771-4k`）构建的 Magisk
内核模块源码，向官方内核注册两个同名高优先级 crypto 压缩驱动：

| 算法 | 驱动名 | priority | 内嵌版本 |
| --- | --- | --- | --- |
| zstd | `zstd-new-generic` | 100 | 1.5.7 |
| lz4 | `lz4-new-generic` | 100 | 1.10.0 |

本仓库只包含源码和构建脚本，不包含编译后的 `.ko` 与 Magisk 安装包。

## 原理

内核内置 zstd/lz4 crypto 驱动的 priority 为 0。模块通过
`crypto_register_alg()` 注册同名算法，priority 设为 100，
因此之后新建的 zram 压缩上下文会优先命中模块提供的实现：

1. Magisk 在开机后加载 `zstd-upgrade.ko` 与 `lz4-upgrade.ko`。
2. `/proc/crypto` 中出现 `zstd-new-generic` / `lz4-new-generic`。
3. zram 写入 `zstd` 或 `lz4` 时，crypto 查找优先返回新驱动。
4. 只影响之后新建的压缩上下文，已经在线的 `zram0` 不会自动切换。
5. 内核导出的 `ZSTD_versionString` 等符号不会改变，仍显示内核内置版本。

## 目录结构

```text
zstd-upgrade/
  src/zstd-upgrade-driver.c    zstd crypto 驱动
  lib/zstd/                    zstd 1.5.7 内核适配源码
  include/linux/               zstd 内核头文件
  scripts/build_zstd_upgrade_ko.sh
lz4-upgrade/
  src/lz4-upgrade-driver.c     lz4 crypto 驱动
  lib/                         lz4 1.10.0 源码
  include/                     自由构建用头文件
  scripts/build_lz4_upgrade_ko.sh
magisk/zstd157-lz410-upgrade/
  module.prop                  模块信息
  customize.sh                 安装提示
  service.sh                   开机自动加载
  load.sh / unload.sh          手动加载/卸载
  zstd-upgrade.sh              状态/加载/卸载控制
  verify.sh                    版本与命中验证
tools/generate_zstd_linux.py   zstd 内核源码生成脚本
```

## 构建

构建需要：

- 与手机同版本内核匹配的解包内核头文件目录
- 可用的 `clang`、`ld.lld`、`llvm-strip`

默认脚本参数面向本机路径，请在克隆后通过环境变量覆盖：

```sh
export QCOM_HEADERS_DIR=/path/to/kernel-headers
export QCOM_CLANG=/usr/bin/clang
export QCOM_LD_LLD=/usr/bin/ld.lld
export QCOM_STRIP=/usr/bin/llvm-strip

sh zstd-upgrade/scripts/build_zstd_upgrade_ko.sh
sh lz4-upgrade/scripts/build_lz4_upgrade_ko.sh
```

生成的 `.ko` 位于各自的 `out/` 目录。把两个 `.ko` 放入
`magisk/zstd157-lz410-upgrade/` 后，可将该目录打包为 Magisk 模块。

## 验证

模块加载后执行：

```sh
adb shell su -c 'sh /data/adb/modules/zstd-upgrade/verify.sh'
```

`verify.sh` 会新建临时 zram 设备，分别选择 zstd 和 lz4，
检查 `zstd-new-generic` / `lz4-new-generic` 的 refcnt 是否增加，
验证后自动移除临时设备，不触碰 `zram0`。

## 风险

- 内核模块加载属于高风险操作，可能触发重启、卡开机或变砖。
- 模块只遮蔽新建压缩上下文，不能替换内核内置算法符号。
- 让 Android 实际切换到新算法还需要修改系统 zram 配置，风险更高。
- 如出现异常，可在 Magisk 中停用模块后重启。

## 许可证

驱动与内核适配源码遵循 GPL-2.0-only，见 [LICENSE](LICENSE)。
