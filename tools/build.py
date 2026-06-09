#!/usr/bin/env python3
"""MoFox-Android 一键打包脚本。

用法:
    python tools/build.py              # debug APK
    python tools/build.py --release    # release APK (未签名)
    python tools/build.py --clean      # 先 flutter clean 再构建
    python tools/build.py --no-pub-get # 跳过 pub get
    python tools/build.py --target-platform android-arm64 --artifact-label arm64-v8a
    python tools/build.py --fetch-bootstrap                  # 构建前下载缺失的 bootstrap zip
    python tools/build.py --fetch-bootstrap-only             # 只下载，不构建

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
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
APP_DIR = REPO_ROOT / "app"
DIST_DIR = REPO_ROOT / "dist"
RUNTIME_ASSETS_DIR = APP_DIR / "assets" / "runtime"

# Termux bootstrap pin。要换版本时只动这里 + RUNTIME_ASSETS_DIR/README.md。
BOOTSTRAP_TAG = "bootstrap-2026.06.07-r1+apt.android-7"
BOOTSTRAP_RELEASE_URL = (
    "https://github.com/termux/termux-packages/releases/download/"
    + urllib.request.quote(BOOTSTRAP_TAG, safe="")
)
BOOTSTRAP_ZIPS = (
    "bootstrap-aarch64.zip",
    "bootstrap-arm.zip",
    "bootstrap-x86_64.zip",
)
TARGET_PLATFORM_TO_ZIP = {
    "android-arm64": "bootstrap-aarch64.zip",
    "android-arm": "bootstrap-arm.zip",
    "android-x64": "bootstrap-x86_64.zip",
}


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


def _is_valid_bootstrap_zip(path: Path) -> bool:
    """README.md 占位符通常 < 4KB；真 zip 至少几 MB 且头 4 字节是 PK\\x03\\x04。"""
    if not path.is_file():
        return False
    if path.stat().st_size < 1024 * 1024:
        return False
    with path.open("rb") as fh:
        head = fh.read(4)
    return len(head) >= 4 and head[0:2] == b"PK" and head[2] in (3, 5, 7)


def fetch_bootstrap_zips(zips: list[str], force: bool = False) -> int:
    """从 termux-packages 下载缺失的 bootstrap zip 到 app/assets/runtime/。"""
    RUNTIME_ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    for name in zips:
        dest = RUNTIME_ASSETS_DIR / name
        if not force and _is_valid_bootstrap_zip(dest):
            print(f"[INFO] {name} 已存在 ({human_size(dest.stat().st_size)})，跳过。")
            continue

        url = f"{BOOTSTRAP_RELEASE_URL}/{name}"
        tmp = dest.with_suffix(dest.suffix + ".part")
        print(f"[INFO] 下载 {name}\n        {url}")
        try:
            with urllib.request.urlopen(url) as resp, tmp.open("wb") as out:
                total = int(resp.headers.get("Content-Length") or 0)
                read = 0
                last_print = 0.0
                while True:
                    chunk = resp.read(64 * 1024)
                    if not chunk:
                        break
                    out.write(chunk)
                    read += len(chunk)
                    now = time.time()
                    if total and now - last_print > 0.5:
                        pct = read / total * 100
                        sys.stdout.write(
                            f"\r        {human_size(read)} / {human_size(total)} ({pct:.1f}%)"
                        )
                        sys.stdout.flush()
                        last_print = now
                if total:
                    sys.stdout.write("\n")
        except Exception as exc:  # noqa: BLE001
            tmp.unlink(missing_ok=True)
            print(f"[ERR] 下载 {name} 失败: {exc}", file=sys.stderr)
            return 1

        if not _is_valid_bootstrap_zip(tmp):
            size = tmp.stat().st_size if tmp.exists() else 0
            tmp.unlink(missing_ok=True)
            print(
                f"[ERR] 下载到的 {name} 不是合法 zip (size={size})。",
                file=sys.stderr,
            )
            return 1
        tmp.replace(dest)
        print(f"        -> {dest}  {human_size(dest.stat().st_size)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="MoFox-Android 一键打包")
    parser.add_argument("--release", action="store_true", help="构建 release APK (未签名)")
    parser.add_argument("--clean", action="store_true", help="构建前 flutter clean")
    parser.add_argument("--no-pub-get", action="store_true", help="跳过 flutter pub get")
    parser.add_argument("--split-per-abi", action="store_true", help="按 ABI 拆分 APK")
    parser.add_argument("--target-platform", help="传给 flutter build apk 的目标平台，例如 android-arm64")
    parser.add_argument("--artifact-label", help="追加到 dist APK 文件名中的标签，例如 arm64-v8a")
    parser.add_argument(
        "--fetch-bootstrap",
        action="store_true",
        help="构建前下载缺失的 bootstrap zip 到 app/assets/runtime/",
    )
    parser.add_argument(
        "--fetch-bootstrap-only",
        action="store_true",
        help="只下载 bootstrap zip 然后退出，不构建",
    )
    parser.add_argument(
        "--force-fetch-bootstrap",
        action="store_true",
        help="强制重新下载，即使本地已有 zip",
    )
    args = parser.parse_args()

    if not APP_DIR.exists():
        print(f"[ERR] 找不到 Flutter 工程目录: {APP_DIR}", file=sys.stderr)
        return 1

    # 决定需要哪些 zip：指定 --target-platform 时只下对应那一个，否则下全套。
    if args.target_platform and args.target_platform in TARGET_PLATFORM_TO_ZIP:
        zips_needed = [TARGET_PLATFORM_TO_ZIP[args.target_platform]]
    else:
        zips_needed = list(BOOTSTRAP_ZIPS)

    if args.fetch_bootstrap or args.fetch_bootstrap_only:
        rc = fetch_bootstrap_zips(zips_needed, force=args.force_fetch_bootstrap)
        if rc != 0:
            return rc
        if args.fetch_bootstrap_only:
            print("[INFO] --fetch-bootstrap-only 完成，跳过构建。")
            return 0

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
    if args.target_platform:
        build_cmd.extend(["--target-platform", args.target_platform])
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
        if args.artifact_label:
            suffix = args.artifact_label if suffix == "universal" else f"{args.artifact_label}-{suffix}"
        out_name = f"mofox-{flavor}-{suffix}-{ts}.apk"
        dest = DIST_DIR / out_name
        shutil.copy2(apk, dest)
        print(f"  [{flavor}] {apk.name}  {human_size(size)}")
        print(f"           -> {dest}")

    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
