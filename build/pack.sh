#!/bin/sh
# 用 python3 打模块包（WSL Ubuntu 自带 python3；Windows 侧没有 zip/7z 的 unix 权限位）。
# 好处：条目路径用 '/'、zip 内带上 unix mode（*.sh 0755、数据文件 0644），
# 以后补 META-INF/com/google/android/update-binary 时也能保持可执行位。
#
# 用法：sh build/pack.sh [输出zip路径]
# 确定性：条目按名字排序、时间戳固定为 2026-01-01，便于比对两次打包结果。

set -e
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MOD="$ROOT/module/piano_zram"
OUT="${1:-$ROOT/release/piano_zram_v1.9.zip}"

python3 - "$MOD" "$OUT" <<'PY'
import os, sys, zipfile

mod, out = sys.argv[1], sys.argv[2]
STAMP = (2026, 1, 1, 0, 0, 0)

exec_ext = ('.sh',)
entries = []
for base, dirs, files in os.walk(mod):
    dirs.sort()
    rel_base = os.path.relpath(base, mod).replace(os.sep, '/')
    for f in sorted(files):
        rel = f if rel_base == '.' else rel_base + '/' + f
        entries.append((rel, os.path.join(base, f)))
    for d in sorted(dirs):
        rel = d if rel_base == '.' else rel_base + '/' + d
        entries.append((rel + '/', None))
entries.sort()

os.makedirs(os.path.dirname(out), exist_ok=True)
if os.path.exists(out):
    os.remove(out)

with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for rel, path in entries:
        ti = zipfile.ZipInfo(rel, date_time=STAMP)
        ti.compress_type = zipfile.ZIP_STORED if path is None else zipfile.ZIP_DEFLATED
        if path is None:
            ti.external_attr = (0o40755 << 16) | 0x10
        else:
            mode = 0o100755 if rel.endswith(exec_ext) else 0o100644
            ti.external_attr = mode << 16
            with open(path, 'rb') as fh:
                data = fh.read()
        z.writestr(ti, b'' if path is None else data)
print('packed %d entries -> %s' % (len(entries), out))
PY
