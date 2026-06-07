#!/usr/bin/env python3
"""MoFox-Android 一键打包脚本。

用法:
    python tools/build.py              # debug APK
    python tools/build.py --release    # release APK (未签名)
    python tools/build.py --clean      # 先 flutter clean 再构建
    python tools/build.py --no-pub-get # 跳过 pub get

输出:
    g:/MoFox-Android/dist/mofox-<flavor>-<timestamp>.apk
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
APP_DIR = REPO_ROOT / "app"
DIST_DIR = REPO_ROOT / "dist"


def find_flutter() -> str:
    """按优先级找 flutter 可执行文件。"""
    # 1. PATH
    found = shutil.which("flutter") or shutil.which("flutter.bat")
    if found:
        return found

    # 2. fvm 默认版本
    candidates = [
        Path.home() / "fvm" / "default" / "bin" / "flutter.bat",
        Path.home() / "fvm" / "default" / "bin" / "flutter",
        Path("C:/src/flutter/bin/flutter.bat"),
        Path("C:/flutter/bin/flutter.bat"),
        Path("/usr/local/flutter/bin/flutter"),
    ]
    for c in candidates:
        if c.exists():
            return str(c)

    # 3. 从注册表 / 环境变量重建 PATH (Windows)
    if sys.platform == "win32":
        try:
            import winreg

            for hive, key_path in [
                (winreg.HKEY_LOCAL_MACHINE, r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment"),
                (winreg.HKEY_CURRENT_USER, r"Environment"),
            ]:
                with winreg.OpenKey(hive, key_path) as key:
                    try:
                        path_val, _ = winreg.QueryValueEx(key, "Path")
                        for p in path_val.split(";"):
                            cand = Path(p) / "flutter.bat"
                            if cand.exists():
                                return str(cand)
                    except FileNotFoundError:
                        pass
        except Exception:
            pass

    print("[ERR] 找不到 flutter，请确认已安装并加入 PATH。", file=sys.stderr)
    print("      可以试着把 flutter\\bin 加到 PATH 后重启终端。", file=sys.stderr)
    sys.exit(127)


def stream_run(cmd: list[str], cwd: Path, env: dict[str, str] | None = None) -> int:
    """实时打印子进程输出，避免 Select-Object 那种缓冲问题。"""
    print(f"\n>> {' '.join(cmd)}  (cwd={cwd})\n", flush=True)
    proc = subprocess.Popen(
        cmd,
        cwd=str(cwd),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        encoding="utf-8",
        errors="replace",
    )
    assert proc.stdout is not None
    for line in proc.stdout:
        sys.stdout.write(line)
        sys.stdout.flush()
    return proc.wait()


def human_size(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f}{unit}"
        n /= 1024
    return f"{n:.1f}TB"


def main() -> int:
    parser = argparse.ArgumentParser(description="MoFox-Android 一键打包")
    parser.add_argument("--release", action="store_true", help="构建 release APK (未签名)")
    parser.add_argument("--clean", action="store_true", help="构建前 flutter clean")
    parser.add_argument("--no-pub-get", action="store_true", help="跳过 flutter pub get")
    parser.add_argument("--split-per-abi", action="store_true", help="按 ABI 拆分 APK")
    args = parser.parse_args()

    if not APP_DIR.exists():
        print(f"[ERR] 找不到 Flutter 工程目录: {APP_DIR}", file=sys.stderr)
        return 1

    flutter = find_flutter()
    print(f"[INFO] 使用 flutter: {flutter}")

    flavor = "release" if args.release else "debug"
    started = time.time()

    # 1. clean (可选)
    if args.clean:
        rc = stream_run([flutter, "clean"], cwd=APP_DIR)
        if rc != 0:
            print(f"[ERR] flutter clean 失败 (exit={rc})", file=sys.stderr)
            return rc

    # 2. pub get
    if not args.no_pub_get:
        rc = stream_run([flutter, "pub", "get"], cwd=APP_DIR)
        if rc != 0:
            print(f"[ERR] flutter pub get 失败 (exit={rc})", file=sys.stderr)
            return rc

    # 3. build apk
    build_cmd = [flutter, "build", "apk", f"--{flavor}"]
    if args.split_per_abi:
        build_cmd.append("--split-per-abi")
    rc = stream_run(build_cmd, cwd=APP_DIR)
    if rc != 0:
        print(f"[ERR] flutter build apk --{flavor} 失败 (exit={rc})", file=sys.stderr)
        return rc

    # 4. 收集产物
    apk_dir = APP_DIR / "build" / "app" / "outputs" / "flutter-apk"
    if not apk_dir.exists():
        print(f"[ERR] 找不到 APK 输出目录: {apk_dir}", file=sys.stderr)
        return 2

    apks = sorted(apk_dir.glob(f"app-{flavor}*.apk"))
    if not apks:
        # 兜底，把目录里所有 apk 都列出来
        apks = sorted(apk_dir.glob("*.apk"))
    if not apks:
        print(f"[ERR] {apk_dir} 下没有 .apk 文件", file=sys.stderr)
        return 2

    DIST_DIR.mkdir(exist_ok=True)
    ts = time.strftime("%Y%m%d-%H%M%S")
    print("\n" + "=" * 60)
    print(f"构建完成，用时 {time.time() - started:.1f}s")
    print("=" * 60)
    for apk in apks:
        size = apk.stat().st_size
        # 命名: mofox-<flavor>-<原文件后缀>-<时间戳>.apk
        suffix = apk.stem.replace(f"app-{flavor}", "").lstrip("-") or "universal"
        out_name = f"mofox-{flavor}-{suffix}-{ts}.apk"
        dest = DIST_DIR / out_name
        shutil.copy2(apk, dest)
        print(f"  [{flavor}] {apk.name}  {human_size(size)}")
        print(f"           -> {dest}")

    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
