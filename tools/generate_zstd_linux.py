import sys
import os
import shutil

base = "/mnt/c/Users/hyq-18T/Documents/Codex/2026-08-11/github/outputs/compression-upgrade-zstd157-lz410"
zstd_src = base + "/src-tmp/zstd-1.5.7"
project_root = base + "/zstd-upgrade"

sys.path.insert(0, zstd_src + "/contrib/freestanding_lib")

import freestanding

linux_root = project_root + "/gen"
shutil.rmtree(linux_root, ignore_errors=True)

args = [
    "--zstd-deps",
    zstd_src + "/contrib/linux-kernel/zstd_deps.h",
    "--mem",
    zstd_src + "/contrib/linux-kernel/mem.h",
    "--source-lib",
    zstd_src + "/lib",
    "--output-lib",
    linux_root + "/lib/zstd",
    "--xxhash",
    "<linux/xxhash.h>",
    "--xxh64-state",
    "struct xxh64_state",
    "--xxh64-prefix",
    "xxh64",
    "--rewrite-include",
    "<limits\\.h>=<linux/limits.h>",
    "--rewrite-include",
    "<stddef\\.h>=<linux/types.h>",
    "--rewrite-include",
    '"../zstd.h"=<linux/zstd.h>',
    "--rewrite-include",
    '"(\\.\\./)?zstd_errors.h"=<linux/zstd_errors.h>',
    "--sed",
    "s,/\\*\\*\\*,/* *,g",
    "--sed",
    "s,/\\*\\*,/*,g",
    "--spdx",
    "-D",
    "ZSTD_NO_INTRINSICS",
    "-D",
    "ZSTD_NO_UNUSED_FUNCTIONS",
    "-D",
    "ZSTD_LEGACY_SUPPORT=0",
    "-D",
    "ZSTD_STATIC_LINKING_ONLY",
    "-D",
    "FSE_STATIC_LINKING_ONLY",
    "-D",
    "XXH_STATIC_LINKING_ONLY",
    "-D",
    "__GNUC__",
    "-D",
    "__linux__=1",
    "-D",
    "STATIC_BMI2=0",
    "-D",
    "ZSTD_ADDRESS_SANITIZER=0",
    "-D",
    "ZSTD_MEMORY_SANITIZER=0",
    "-D",
    "ZSTD_DATAFLOW_SANITIZER=0",
    "-D",
    "ZSTD_COMPRESS_HEAPMODE=1",
    "-U",
    "NO_PREFETCH",
    "-U",
    "__cplusplus",
    "-U",
    "ZSTD_DLL_EXPORT",
    "-U",
    "ZSTD_DLL_IMPORT",
    "-U",
    "__ICCARM__",
    "-U",
    "ZSTD_MULTITHREAD",
    "-U",
    "_MSC_VER",
    "-U",
    "_WIN32",
    "-R",
    "ZSTDLIB_VISIBLE=",
    "-R",
    "ZSTDERRORLIB_VISIBLE=",
    "-R",
    "ZSTD_FALLTHROUGH=fallthrough",
    "-D",
    "ZSTD_HAVE_WEAK_SYMBOLS=0",
    "-D",
    "ZSTD_TRACE=0",
    "-D",
    "ZSTD_NO_TRACE",
    "-D",
    "ZSTD_DISABLE_ASM",
    "-D",
    "ZSTD_LINUX_KERNEL",
]

freestanding.main("freestanding.py", args)

lib_root = linux_root + "/lib/zstd"
os.remove(lib_root + "/decompress/huf_decompress_amd64.S")
shutil.rmtree(project_root + "/lib", ignore_errors=True)
shutil.rmtree(project_root + "/include", ignore_errors=True)
shutil.move(lib_root, project_root + "/lib/zstd")
os.makedirs(project_root + "/include/linux", exist_ok=True)
shutil.move(project_root + "/lib/zstd/zstd.h", project_root + "/include/linux/zstd_lib.h")
shutil.move(project_root + "/lib/zstd/zstd_errors.h", project_root + "/include/linux/zstd_errors.h")
shutil.copy2(
    zstd_src + "/contrib/linux-kernel/linux_zstd.h",
    project_root + "/include/linux/zstd.h",
)
shutil.rmtree(linux_root, ignore_errors=True)
