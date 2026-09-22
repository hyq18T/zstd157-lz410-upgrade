# zstd 1.5.7 + lz4 1.10.0 内核压缩算法升级模块

面向小米 15 Pro（haotian / 2410DPN6CC，HyperOS `OS3.0.309.0.WOBCNXM`，内核
`6.6.118-android15-8-gc44b714366cc-abogki519650608-4k`）构建的 Magisk 内核模块源码。
模块向官方内核注册两个同名高优先级 crypto 压缩驱动，让新建的 zram 压缩上下文优先命中新版实现。

| 算法 | 驱动名 | priority | 内嵌版本 |
| --- | --- | --- | --- |
| zstd | `zstd-new-generic` | 100 | 1.5.7 |
| lz4 | `lz4-new-generic` | 100 | 1.10.0 |

本仓库只包含源码、模块脚本与构建工具，**不包含编译后的 `.ko` 与 Magisk 安装包**
（`.ko` 只对特定内核有效，见 `release/SHA256SUMS-v1.9.txt` 记录的产物指纹）。

## 原理

真机 `/proc/crypto` 实测：内置 `zstd-generic` / `zstd-scomp` / `lz4-generic` / `lz4-scomp`
的 `cra_priority` **全部是 0**，所以同名注册 `priority = 100` 即可在按 `cra_name`
的模糊查找中胜出（真机 `zram.ko` 导入 `crypto_alloc_base` / `crypto_comp_compress`，
走的是传统 `CRYPTO_ALG_TYPE_COMPRESS` 路径，不是 scomp）：

1. `post-fs-data.sh` 在 Perfinit 创建 `zram0` **之前**注册两个新驱动。
2. `/proc/crypto` 出现 `zstd-new-generic` / `lz4-new-generic`，priority 100。
3. zram 写入 `zstd` 或 `lz4` 时命中新驱动。
4. 只影响注册之后新建的压缩上下文；已经在线的 `zram0` 不会自动切换。
5. 内核导出的 `ZSTD_versionString` 等符号不变，仍显示内置版本。

### 怎么判断“真的用上了”——只看 refcnt

`comp_algorithm` 显示 `[zstd]` **不代表**用的是新驱动：内置与新版都叫 `zstd`。
唯一可靠的判据是 `/proc/crypto` 里的 refcnt（8 核机上服务 zram0 的那个约等于 9，没被用的是 1）：

```sh
grep -A5 "zstd-new-generic" /proc/crypto | grep refcnt   # 期望 ≈9
grep -A5 "zstd-generic"     /proc/crypto | grep refcnt   # 期望 1
```

本仓库的 `zram-algo.sh` 与 `verify.sh` 都按这个判据写；一条历史教训见
[docs/v1.9-验证记录.md](docs/v1.9-验证记录.md) 第 14 节：早期版本只比较算法名，
`zram0 already zstd, no rebuild` 会让“注册了但没人用”被当成成功。

## 唯一的限制：内核必须匹配

`magisk/piano_zram/bin/kernel-check.sh` 是这个模块唯一的硬性检查，三处生效：

| 时机 | 不匹配时的行为 |
| --- | --- |
| 安装（`customize.sh`） | 先于三问执行，打印原因并 `abort`，模块不会被安装 |
| `post-fs-data.sh` | 不注册驱动、不覆盖 `perfinit.conf`，只记日志 |
| `service.sh` | 不 insmod、不重建 `zram0`，只记日志 |

期望值不写死在脚本里，而是现场从包内 `bin/zstd-upgrade.ko` 的 `.modinfo vermagic` 读取，
保证“脚本声称的内核”和“二进制要求的那个内核”永远一致。三种情况分别给出解释：
内核不对（附按当前内核重编的命令）、包不完整（提示校验 sha256）、刷入环境异常（`uname -r` 读不出）。

之所以这么硬：本内核 `CONFIG_MODVERSIONS=y` 且 `CONFIG_MODULE_FORCE_LOAD` **未开**，
vermagic 或符号 CRC 不符时 `insmod` 必被拒（`-ENOEXEC`），装上等于没装。

## 目录结构

```text
zstd-upgrade/            zstd 1.5.7 内核适配源码 + crypto 驱动 + 构建脚本
lz4-upgrade/             lz4 1.10.0 源码 + crypto 驱动 + 构建脚本
magisk/piano_zram/       v1.9 模块脚本（安装菜单/开机流程/内核闸门/验证）详见其 README.md
build/
  BUILD-6.6.118.sh       两个 .ko 的构建封装（含换内核检查清单）
  pack.sh                打模块 zip（python3，写入 unix 权限位、条目确定性）
release/
  SHA256SUMS-v1.9.txt    v1.9 交付物的指纹（zip 与 .ko 本体不入库）
docs/
  v1.9-验证记录.md        真机证据、符号 CRC 核验、闸门与按键的测试记录
tools/generate_zstd_linux.py
                           用上游 freestanding.py 把官方 zstd 生成内核版
```

## 构建

需要与手机同版本、已解包的内核头文件，以及 `clang` / `ld.lld` / `llvm-strip`
（内核由 clang 18.0.0 构建，编译模块请用同大版本——`CONFIG_CFI_CLANG=y` 下 KCFI typeid 由编译器算出）：

```sh
sh build/BUILD-6.6.118.sh /path/to/本仓库 /path/to/kernel-headers
# 可用环境变量覆盖：QCOM_HEADERS_DIR QCOM_VERMAGIC QCOM_CLANG QCOM_LD_LLD QCOM_STRIP OUT
```

产物落在 `$OUT/zstd/zstd-upgrade.ko` 与 `$OUT/lz4/lz4-upgrade.ko`。
已实测该脚本可复现出与 v1.9 交付版逐字节一致的 `.ko`。

换内核时的检查清单（写在 `build/BUILD-6.6.118.sh` 注释里）：

1. headers 必须来自运行内核（`/sys/kernel/kheaders.tar.xz`），并核对 `kernel.release`。
2. `QCOM_VERMAGIC` 用当前 `uname -r` 拼（后缀固定
   ` SMP preempt mod_unload modversions aarch64`）。
3. **重新核对符号 CRC**：构建脚本里那张表是写死的。真机办法是反解任意厂商 `.ko` 的
   `__versions` 段（步长 64：`unsigned long crc` + `char name[56]`）——那些就是运行内核要求的值。
   本仓库当前这版已在 6.6.118 上核对过：`module_layout`、`vmalloc`、`vfree`、`memset`、
   `memcpy`、`memmove` 六项与旧值一致；`crypto_register_alg`/`crypto_unregister_alg`
   厂商模块没有导入者、取不到实测值，靠 `insmod` 成功来最终证明。
4. 重跑 `tools/generate_zstd_linux.py` 会用上游源码覆盖 `zstd-upgrade/lib`，
   并**丢掉 `common/xxhash.c` 里的本地 xxh64 补丁**（内核不导出 `xxh64_*` 给模块用），
   重生成后需要重新打上，否则链接期会报未定义符号。

打包成可安装 zip：

```sh
sh build/pack.sh            # 生成 release/piano_zram_v1.9.zip
```

zip 里文件位于根目录、无 `META-INF`，走 Magisk（管理器或 `magisk --install-module`）安装；
要在 recovery 里直接卡刷还需要 `META-INF/com/google/android/update-binary`，本仓库没有提供。

## 安装与验证

```sh
adb push piano_zram_v1.9.zip /data/local/tmp/
adb shell su -c 'magisk --install-module /data/local/tmp/piano_zram_v1.9.zip'
adb reboot
adb shell su -c 'sh /data/adb/modules/piano_zram/bin/verify.sh'
```

安装时三项各管一件事，全部是**音量上切换 / 音量下确认 / 20 秒未按用当前项**：

1. MI Piano 系统调优（VM/IO/F2FS 参数；系统自带且未加载的内核模块才补加载）。
2. 装不装新驱动（`zstd-upgrade.ko` + `lz4-upgrade.ko` 注不注册）。
3. `zram0` 用哪个算法：`lz4` / `zstd` / `不改(回/留系统默认)`。
   系统默认取内核编译期的 `CONFIG_ZRAM_DEF_COMP`（本机为 `lzo-rle`），与 zram0 当前状态无关。

选第 3 项“不改”时：新驱动照第 2 项的选择注册，但不覆盖 `perfinit.conf`、不重建 `zram0`、
不动 `page-cluster`；想临时试就 `sh bin/zram-algo.sh apply zstd`。

## 风险

- 内核模块加载属高风险操作，可能重启、卡开机或变砖；异常时在 Magisk 停用本模块后重启。
- 只遮蔽新建的压缩上下文，不替换内核内置算法符号，也不能在线切换已运行的 `zram0`。
- 注册后所有按 `cra_name="zstd"/"lz4"` 查找的使用方都会命中新驱动，属全局变更。
  本机实测（供参考）：`/data` 的 f2fs 未开 `compressed`、erofs 镜像未启用压缩，
  且除 zram 外没有别的持有者，实际影响面就是 zram。
- zstd 侧硬编码 level 3（`ZSTD_UPGRADE_LEVEL`），与内置实现的级别不同，压缩比与 CPU 占用都会变；
  且每个 tfm 会 `vmalloc` 一整套 CCtx+DCtx，按 CPU 数叠加，是额外的常驻内存。
- 内嵌 lz4 1.10.0 输出不带长度头的纯 LZ4 block，与内置驱动的产物**不互通**；
  同一个 zram 设备自始至终只持有一个 tfm，所以自洽，但不要跨驱动混用数据。
- zram0 切换是 `swapoff → reset → 设算法 → disksize → mkswap → swapon`，中途失败（常见于
  `swapoff` 因内存吃紧失败）会留一个本次开机没有交换的状态，补救是重跑 `zram-algo.sh apply` 或重启。

## 许可证

驱动与内核适配源码遵循 GPL-2.0-only，见 [LICENSE](LICENSE)。
