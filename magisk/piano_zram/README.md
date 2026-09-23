# MI Piano 系统调优 + 压缩算法升级（v1.9，针对 6.6.118 新内核）

机型：小米 15 Pro（`2410DPN6CC` / haotian）
系统：`OS3.0.309.0.WOBCNXM`
**目标内核：`6.6.118-android15-8-gc44b714366cc-abogki519650608-4k`（只认这个 vermagic，换内核需重编）**

安装包：`release/piano_zram_v1.9.zip`
构建与核验细节见 `验证记录-v1.9.txt`。

## 唯一的限制：内核必须是本包编译时的那个

这是整个模块**只有的一道硬性检查**，三处生效：

| 时机 | 行为 |
| --- | --- |
| 安装（`customize.sh`） | 先于三问执行；不通过就打印完整解释并 `abort`，**模块不会被安装** |
| `post-fs-data.sh` | 不通过就不 bind 覆盖 `perfinit.conf`，只记日志 |
| `service.sh` | 不通过就不 insmod、不重建 `zram0`，只记日志（`service.log` 里是可读的中文原因） |

期望值**不写在脚本里**，而是现场从包内 `bin/zstd-upgrade.ko` 的 `.modinfo` 里读
（`bin/kernel-check.sh`），所以“脚本声称的内核”和“二进制真正要求的那个内核”永远一致。
三种情况会被挡住并分别给出对应解释：

- 内核不对（比如又更新了系统）→ 说明为什么 insmod 会被拒（vermagic + 符号 CRC 写死，`-ENOEXEC`），
  并给出两条出路：按当前内核重编（命令直接给全，`VERMAGIC` 用你当前 `uname -r` 填好），或刷回适用版本。
- 包不完整/被解坏（`.ko` 读不到、`.modinfo` 里没有 vermagic）→ 让你对照 `release/SHA256SUMS.txt`
  重新校验 sha256 再重新推送，别拿别的机型的包替代。
- 刷入环境异常（`uname -r` 读不出来）→ 提示确认 Magisk 已安装，并给出两种正确的刷入方式。

实现上有一个只有真机才暴露的坑，改这个文件时别再踩：读 `.ko` 里的 vermagic **不能**用
`tr -c '[:print:]' '\n' < 文件` 再 `sed` —— Android 的 toybox `tr` 会把整段内容压成一堆换行，
结果永远读不到值，**正确的包也会被自己的闸门拦下**（在 WSL/GNU 下却是好的）。现在统一用
`grep -ao 'vermagic=[^ ]*'`，并已在真机复验：两个 `.ko` 都判 PASS，`.ko` 缺失时正确拦住并提示校验
sha256。`verify.sh` 第 0 步用的是同一套写法。

## v1.9 相对 v1.8 改了什么

1. **两个 `.ko` 全部按新内核重编**（zstd 1.5.7 / lz4 1.10.0，源码与你 GitHub 仓库完全同源，
   一字未改）。v1.8 里那两个是 6.6.77 的，在新内核上 insmod 会被直接拒绝。
2. **音量键交互改了**：以前是“按音量上就等于选中第一个”，现在是
   **音量上 = 在选项间循环切换，音量下 = 确认当前高亮项**；超时（20s）用当前高亮项。
3. **第 3 项新增“不改算法”选项，并且三项职责彻底分开**（这一条是照你的意思改的）：
   `lz4` / `zstd` / **不改（保持系统默认，实测是 lzo-rle）** 三选一。
   - 第 1 项只管 MI Piano 调优；第 2 项只管**装不装新驱动**；第 3 项只管 **zram0 用哪个算法**。
   - 所以：第 2 项启用、第 3 项选“不改”时，**两个新驱动照样 insmod 注册**（`/proc/crypto` 里能看到
     `zstd-new-generic`/`lz4-new-generic`，随时可手动切），只是不去覆盖 `perfinit.conf`、
     不重建 `zram0`、不动 `page-cluster`。想让某个新建的 zram 用新算法，`zram-algo.sh apply zstd` 即可。
   - 只有第 2 项选“跳过”时才真的什么都不加载。
4. **不再打包那 5 个 MI Piano `.ko`**。新系统实测：`binder_prio`、`kshrink_slabd` 系统自带且自己
   就会加载；`mi_async_reclaim`、`mi_rmap_efficiency`、`ntsync` 在新系统里已经不存在（也没有源码，
   无法为新内核重编）。v1.9 的做法是：**只对系统里确实存在的模块做“没加载就补加载”**，
   永远不用陈旧二进制；其余调优（VM/IO/F2FS 参数）保持不变。
   补充实测：`/vendor/lib/modules/binder_prio.ko` 是上个 ROM 留下的 **6.6.57** 陈旧副本，
   而本内核 `CONFIG_MODULE_FORCE_LOAD` 未开 —— 这种文件加载必被拒，所以“补加载”也要先比 vermagic
   再决定，不匹配就跳过并在 `service.log` 写清原因。
5. **新增内核闸门**（见上一节）：`bin/kernel-check.sh`，安装/开机三处生效，不匹配就中止并解释。
   `versionCode` 相应升到 191。
6. `verify.sh` 增加第 0 步：**直接比对 `.ko` 里的 vermagic 和 `uname -r`**，换内核后一眼能看出
   是不是包不匹配。

## 安装（走 Magisk，不走 recovery 直刷）

```sh
adb push /d/piano_zram_v1.9.zip /data/local/tmp/
adb shell su -c 'magisk --install-module /data/local/tmp/piano_zram_v1.9.zip'
adb reboot
```

> 关于 recovery 直刷：包里**没有** `META-INF/com/google/android/update-binary`（v1.8 也没有），
> 在 TWRP/OrangeFox 里直接选这个 zip 大概率被当成无效包。我不凭记忆手写那段官方脚本
> （它跑在开机第一步，且我这边没有任何 recovery 可测）。你要是手上有任意一个能在 recovery
> 直接刷的模块包，把那个 zip 给我，我 `unzip -p <它> META-INF/com/google/android/update-binary`
> 原样取出模板补进包 —— `build/pack.sh` 已经会写 unix 权限位（`update-binary` 要 0755），
> 补进去只是加两个文件的事。

安装过程中依次三问，全部是 **音量上切换 / 音量下确认**。刷入界面不会自动换行、横滑很难受，
所以所有输出都压到 26 列以内（内核名那种长串会断行续打），只需要上下滑：

```text
[1/3] MI Piano 调优
 VM/IO/F2FS 参数调优
 >1. 启用
  2. 跳过
 上:切换 下:确认
 20秒未按=当前项

[2/3] 新驱动
 zstd 1.5.7 + lz4 1.10.0
 注册高优先级 crypto 驱动
 >1. 启用
  2. 跳过

[3/3] zram0 用哪个算法
 只决定 zram0 算法；
 新驱动照上面选择加载
 系统默认:lzo-rle
 当前显示:lzo-rle
 >1. lz4
  2. zstd
  3. 不改(回/留lzo-rle)
```

### 选 zstd 和选“不改”到底差在哪

| 第 3 项 | zram0 用的算法名 | 压页时实际调用 | 结果 |
| --- | --- | --- | --- |
| `lz4` | lz4 | **lz4-new-generic**（lz4 1.10.0） | 用上新实现 |
| `zstd` | zstd | **zstd-new-generic**（zstd 1.5.7） | 用上新实现 |
| `不改` | 系统默认 lzo-rle | 内置 `lzo-rle-generic` | 完全不碰 zram 配置 |

两个新驱动（`zstd-new-generic`/`lz4-new-generic`）在第 2 项启用时都会注册，但**只有被 zram0 选中
的那个算法名才会真正压页**；选 `lz4` 时 zstd 驱动只是挂着没人用，反之亦然。所以 `zstd` 与 `不改`
的区别是实打实的：前者让 zram0 用 1.5.7 压，后者连算法都不换。

顺带修掉两处标签问题（你指出的那个）：
- 之前“不改”后面的括号里印的是 **zram0 当前的算法**，而当前算法可能正是上一次安装改出来的
  （比如上次选了 zstd，这次就显示成 `不改(保持zstd)`，跟选项 2 分不清）。现在“系统默认”改成读
  `CONFIG_ZRAM_DEF_COMP`（本内核实测是 `lzo-rle`，与 zram0 现状无关），当前值单独一行显示。

错过按键不要紧：超时按当前高亮项（即第 1 项），重启前还能手改：

```sh
echo 'lz4|zstd|default' > /data/adb/modules_update/piano_zram/zram_algo
touch  /data/adb/modules_update/piano_zram/enable_piano      # 启用第 1 项
rm -f  /data/adb/modules_update/piano_zram/enable_piano      # 关闭第 1 项
touch  /data/adb/modules_update/piano_zram/enable_zram       # 启用第 2 项
rm -f  /data/adb/modules_update/piano_zram/enable_zram       # 关闭第 2 项
```

## 开机后验证

```sh
adb shell su -c 'sh /data/adb/modules/piano_zram/bin/verify.sh'
```

会依次输出：`.ko` 与运行内核是否匹配 → 加载状态 → `/proc/crypto` 里 `zstd-new-generic` /
`lz4-new-generic` 是否 priority 100 → **新建临时 zram 的 refcnt 实证**（证明请求真的命中新驱动，
而不是悄悄退回内置旧版）→ `perfinit.conf` 覆盖是否生效 → `zram0` 现状。临时 zram 用完自动移除，
不碰 `zram0`，不改交换配置。第 3 项选了“不改算法”时，它照样会检查新驱动有没有注册、临时 zram 的
refcnt 实证也照跑（这就是“驱动确实可用但没被用上”），只有“zram0 必须等于所选算法”那一条不判定。

一条命令就能看出新驱动**是不是真的在压页**（refcnt 大于 1 才算在用；8 核机上服务 zram0 的那个约等于 9）：

```sh
grep -A5 "zstd-new-generic" /proc/crypto | grep refcnt   # 我们的 1.5.7
grep -A5 "zstd-generic"     /proc/crypto | grep refcnt   # 内置 1.5.2
```

新驱动的注册点已经从 `service.sh`（late_start，晚于 zram 创建）提前到 `post-fs-data.sh`：
Perfinit 第一次建 `zram0` 时就该命中新驱动，正常开机不再需要 swap 重建；万一还是晚了一步，
`zram-algo.sh` 会按上面的 refcnt 判断强制重建一次（不再只看算法名是否相等）。

手工切换（不重启）：

```sh
sh /data/adb/modules/piano_zram/bin/zram-algo.sh status
sh /data/adb/modules/piano_zram/bin/zram-algo.sh apply zstd
sh /data/adb/modules/piano_zram/bin/zram-algo.sh apply default
```

## 回退

```sh
# 只关算法、保留模块：改成保持默认后重启
echo default > /data/adb/modules/piano_zram/zram_algo && reboot
# 或在 Magisk 里停用本模块后重启
# 彻底卸载：Magisk 里卸载，或 rm -rf /data/adb/modules/piano_zram && reboot
```

卸载脚本只回收本模块自己注册的两个驱动，不会去 `rmmod` 系统自带的 `binder_prio`/`kshrink_slabd`。
若 `zram0` 正持有新驱动的 tfm，`rmmod` 会失败，重启后自然回到系统默认算法。

## 风险与边界

- **只遮蔽、不替换**：内置 zstd 1.5.2 / 内置 lz4 的代码还在内核里，只是之后**新建**的压缩上下文
  优先命中新驱动。已经在线的 `zram0` 不会自动切换 —— 所以本模块的做法是在开机流程里
  `swapoff → reset → 设算法 → disksize → mkswap → swapon` 重建一次 `zram0`（v1.6 起就是这个逻辑）。
- 新驱动是全局遮蔽（任何按 `cra_name="zstd"/"lz4"` 查找的使用方都会命中）。本次实测：当前系统里
  这两个算法名只有 zram 在用（其余驱动 refcnt 均为 1），且 `/data` 的 f2fs 没开 `compressed`、
  erofs 镜像不是压缩的，所以落盘数据格式不受影响。
- 第 3 项选“跳过 zram0 改动”时，`zram-algo.sh` 与 `verify.sh` 都按“未改动即正确”处理；
  第 2 项选“跳过”时 `verify.sh` 只做只读汇报，不会因为“新驱动 MISSING”判 FAIL。
- `zram0` 切换是 `swapoff → reset → 设算法 → disksize → mkswap → swapon`。如果中途某一步失败
  （最常见是 `swapoff` 因内存吃紧失败），本次开机就可能**没有交换**，表现为后台留存变差。
  补救：`sh bin/zram-algo.sh apply <算法>` 重来一次，或重启；`service.log` 里会写明卡在哪一步。
- 压缩等级是驱动里写死的 **zstd level 3**（内置用的是它自己的等级），这会同时影响压缩比和 CPU 占用；
  要改就改 `zstd-upgrade/src/zstd-upgrade-driver.c` 里的 `ZSTD_UPGRADE_LEVEL` 重编。
- 每个 zram 压缩流会 `vmalloc` 一整套 CCtx+DCtx，按 CPU 数叠加，这是相对内置实现的额外常驻内存。
- 内嵌的 lz4 1.10.0 输出的是**不带长度头**的纯 LZ4 block。同一个 zram 设备自始至终只持有一个 tfm，
  所以自洽；但**不要指望新驱动的产物能被内置驱动读懂**（反之亦然）。
- insmod 内核模块属高风险动作。本包在你没有确认前不会自动装到手机上；第一次建议先手动
  `insmod` + `verify.sh`，确认无误再重启依赖它。

## 目录

```text
piano-zram-combined-v1.9-20260922/
├── README.md                     本文件
├── 验证记录-v1.9.txt              真机只读探测 + CRC 核验 + 构建 + 按键测试记录
├── build/
│   ├── BUILD-6.6.118.sh          重编两个 .ko 的封装脚本（已实测可复现）
│   ├── pack.sh                     打包脚本（python3，写 unix 权限位、条目确定序）
│   └── 源码/                       你的 zstd157-lz410-upgrade 仓库副本（未改动）
├── module/piano_zram/            模块内容（与 zip 内布局一致）
└── release/
    ├── piano_zram_v1.9.zip       安装包
    └── SHA256SUMS.txt
```
