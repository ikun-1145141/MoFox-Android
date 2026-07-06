#!/usr/bin/env python3
"""MoFox-Android 一键打包脚本。

新架构 (jniLibs + bare proot + Debian 13 rootfs)：

    app/android/app/src/main/jniLibs/<abi>/   <- 6 个原生 .so，必须就位
    app/assets/rootfs/debian-13-<abi>.tar.xz

构建前会做资产预检；缺哪个就报哪个，绝不拿不完整的 APK 出门。

用法:
    python tools/build.py                              # debug APK (universal)
    python tools/build.py --release                    # release APK (未签名)
    python tools/build.py --clean                      # 先 flutter clean
    python tools/build.py --no-pub-get                 # 跳过 pub get
    python tools/build.py --target-platform android-arm64 --artifact-label arm64-v8a
    python tools/build.py --check-assets               # 只跑资产预检
    python tools/build.py --skip-asset-check           # 跳过预检 (CI 临时调试用)
    python tools/build.py --fetch-rootfs               # 下载 Debian 13 (trixie) rootfs
    python tools/build.py --fetch-rootfs-only          # 只下载 rootfs 不构建

输出:
    g:/MoFox-Android/dist/mofox-<flavor>-<label>-<timestamp>.apk
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
APP_DIR = REPO_ROOT / "app"
DIST_DIR = REPO_ROOT / "dist"
ROOTFS_DIR = APP_DIR / "assets" / "rootfs"
JNILIBS_DIR = APP_DIR / "android" / "app" / "src" / "main" / "jniLibs"

# 与 RootfsInstaller.kt / build.gradle.kts 保持一致。
# 只支持 arm64-v8a：32 位 ARM 装不了 napcat (Node.js 上游不再维护 armv7)，x86 安卓用户极少。
ABIS = ("arm64-v8a",)
ABI_TO_ROOTFS_SUFFIX = {
    "arm64-v8a": "arm64",
}
ROOTFS_NAME_FMT = "debian-13-{suffix}.tar.xz"

# Debian 13 (trixie) rootfs 从 LXC images 镜像拉。LXC 上游每天 rebuild，目录名是
# 时间戳 (例 20260608_05:24/)，需要先列目录抓最新一项再下 rootfs.tar.xz。
# 镜像顺序：清华 → BFSU → 上游官方。华为云没镜像 lxc-images 这条线。
LXC_DEBIAN_BASE_URLS = (
    "https://mirrors.tuna.tsinghua.edu.cn/lxc-images/images/debian/trixie/{lxc_arch}/default/",
    "https://mirrors.bfsu.edu.cn/lxc-images/images/debian/trixie/{lxc_arch}/default/",
    "https://images.linuxcontainers.org/images/debian/trixie/{lxc_arch}/default/",
)
LXC_TIMESTAMP_RE = re.compile(r"(\d{8}_\d{2}:\d{2})/")

# 与 RuntimeCommandBuilder / RuntimeScripts 调用对齐。
REQUIRED_SO = (
    "libbash.so",
    "libbusybox.so",
    "libproot.so",
    "libsudo.so",
    "libloader.so",
    "liblibtalloc.so.2.so",
)

TARGET_PLATFORM_TO_ABI = {
    "android-arm64": "arm64-v8a",
}


def find_flutter() -> str:
    """按优先级找 flutter 可执行文件。"""
    found = shutil.which("flutter") or shutil.which("flutter.bat")
    if found:
        return found

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
    sys.exit(127)


def stream_run(cmd: list[str], cwd: Path, env: dict[str, str] | None = None) -> int:
    """实时打印子进程输出。"""
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


def human_size(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f}{unit}"
        n /= 1024
    return f"{n:.1f}TB"


def _is_real_tarball(path: Path) -> bool:
    """README 占位通常 < 4KB；真 tar.xz 至少几十 MB 且头是 0xFD 7zXZ。"""
    if not path.is_file():
        return False
    if path.stat().st_size < 1024 * 1024:
        return False
    with path.open("rb") as fh:
        head = fh.read(6)
    return head == b"\xfd7zXZ\x00"


def _is_real_so(path: Path) -> bool:
    """真 ELF 共享库；占位 README 不是 ELF。

    libsudo.so 是 fake sudo 壳脚本（2 字节 `$@`），proot 容器内 uid 已被 -0 映射成
    root，所以 sudo 不需要真实现，让 shell 把参数原样 exec 即可。这里单独放行。
    """
    if not path.is_file():
        return False
    if path.name == "libsudo.so":
        return path.stat().st_size > 0
    if path.stat().st_size < 1024:
        return False
    with path.open("rb") as fh:
        head = fh.read(4)
    return head == b"\x7fELF"


def _http_get_text(url: str, timeout: float = 30.0) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "MoFox-Android-build/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", errors="replace")


def _list_lxc_timestamps(base_url: str) -> list[str]:
    """列 LXC default/ 目录，返回排序后的时间戳列表（旧→新）。"""
    html = _http_get_text(base_url)
    stamps = sorted(set(LXC_TIMESTAMP_RE.findall(html)))
    return stamps


def _resolve_lxc_urls(lxc_arch: str, max_versions: int = 3) -> list[str]:
    """收集所有镜像源的最新 N 个时间戳 rootfs.tar.xz 直链。

    镜像站正在 sync 时，最新时间戳目录已创建但 rootfs.tar.xz 尚未上传完，
    会导致 404。所以收集最近 max_versions 个时间戳，下载时从新到旧依次尝试。

    关键：每个镜像源只用自己的时间戳生成 URL，不会用镜像 A 的时间戳去拼
    镜像 B 的地址——否则镜像 B 还没同步到那个版本就会无辜 404。
    最终候选列表按时间戳从新到旧排序，同一时间戳多镜像源时优先清华→BFSU→上游。
    """
    # stamp → [url1, url2, ...]  （同一时间戳可能有多个镜像源）
    stamp_to_urls: dict[str, list[str]] = {}

    for base_fmt in LXC_DEBIAN_BASE_URLS:
        base = base_fmt.format(lxc_arch=lxc_arch)
        try:
            stamps = _list_lxc_timestamps(base)
        except Exception as exc:  # noqa: BLE001
            print(f"[warn] 列 {base} 失败: {exc}")
            continue

        if not stamps:
            print(f"[warn] {base} 没匹配到时间戳目录")
            continue

        recent = stamps[-max_versions:]
        print(f"[lxc] {lxc_arch} 镜像源 {base}  可用版本: {', '.join(recent)}")
        for stamp in recent:
            url = f"{base}{stamp}/rootfs.tar.xz"
            stamp_to_urls.setdefault(stamp, []).append(url)

    if not stamp_to_urls:
        raise RuntimeError(
            f"所有 LXC 镜像源都没列出 {lxc_arch}/default/ 目录"
        )

    # 按时间戳从新到旧排列；同一时间戳内按镜像源顺序（清华→BFSU→上游）。
    candidates: list[str] = []
    for stamp in sorted(stamp_to_urls.keys(), reverse=True):
        candidates.extend(stamp_to_urls[stamp])
    return candidates


# 下载超时：连接阶段 30s，读取阶段每 chunk 60s。
# 不设 timeout 的话，CI 遇到挂起的镜像站会卡死直到被 GitHub 强杀（6h）。
_DL_CONNECT_TIMEOUT = 30.0
_DL_READ_TIMEOUT = 60.0


def _download_with_progress(url: str, dest: Path) -> None:
    """流式下载到 dest.part，带进度条。

    异常时自动清理 .part 残留，避免垃圾文件遗留。
    """
    tmp = dest.with_suffix(dest.suffix + ".part")
    print(f"[fetch] {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "MoFox-Android-build/1.0"})
    try:
        with urllib.request.urlopen(
            req, timeout=_DL_READ_TIMEOUT
        ) as resp, tmp.open("wb") as out:
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
    except Exception:
        # 中途断开 / 超时 → 清理 .part 残留，不让垃圾文件遗留
        if tmp.exists():
            tmp.unlink()
        raise
    tmp.replace(dest)


def fetch_rootfs(abis: list[str], force: bool = False) -> int:
    """按 ABI 拉 Debian 13 (trixie) rootfs.tar.xz。来源: LXC images 镜像。

    镜像站正在 sync 时最新版本可能 404，所以从新到旧依次尝试多个候选 URL。
    """
    ROOTFS_DIR.mkdir(parents=True, exist_ok=True)

    for abi in abis:
        suffix = ABI_TO_ROOTFS_SUFFIX[abi]
        xz_path = ROOTFS_DIR / ROOTFS_NAME_FMT.format(suffix=suffix)
        if not force and _is_real_tarball(xz_path):
            print(f"[skip] {xz_path.name} 已存在 ({human_size(xz_path.stat().st_size)})")
            continue

        try:
            candidates = _resolve_lxc_urls(suffix)
        except Exception as exc:  # noqa: BLE001
            print(f"[ERR] 解析 {suffix} 镜像源失败: {exc}", file=sys.stderr)
            return 1

        downloaded = False
        for url in candidates:
            try:
                _download_with_progress(url, xz_path)
            except urllib.error.HTTPError as exc:
                if exc.code == 404:
                    print(f"[warn] {url} 返回 404（镜像可能正在 sync），尝试下一个版本…")
                    # 清理 .part 残留
                    part = xz_path.with_suffix(xz_path.suffix + ".part")
                    if part.exists():
                        part.unlink()
                    continue
                raise
            except Exception as exc:  # noqa: BLE001
                print(f"[warn] 下载 {url} 失败: {exc}，尝试下一个版本…")
                part = xz_path.with_suffix(xz_path.suffix + ".part")
                if part.exists():
                    part.unlink()
                continue

            if not _is_real_tarball(xz_path):
                print(f"[warn] {url} 下载产物不是合法 .tar.xz，尝试下一个版本…")
                xz_path.unlink(missing_ok=True)
                continue

            print(f"[ok] {xz_path.name}  {human_size(xz_path.stat().st_size)}")
            downloaded = True
            break

        if not downloaded:
            print(
                f"[ERR] 下载 {suffix} 失败: 所有候选 URL 均不可用",
                file=sys.stderr,
            )
            return 1

    return 0


def check_assets(abis: list[str]) -> int:
    """返回缺失资产数量；0 表示一切就绪。"""
    print(f"[check] ABIs: {', '.join(abis)}")
    missing = 0

    for abi in abis:
        suffix = ABI_TO_ROOTFS_SUFFIX[abi]
        tarball = ROOTFS_DIR / ROOTFS_NAME_FMT.format(suffix=suffix)
        if _is_real_tarball(tarball):
            print(f"  [ok]  rootfs  {tarball.name}  {human_size(tarball.stat().st_size)}")
        else:
            print(f"  [MISS] rootfs  {tarball}")
            missing += 1

        abi_dir = JNILIBS_DIR / abi
        for so_name in REQUIRED_SO:
            so_path = abi_dir / so_name
            if _is_real_so(so_path):
                print(f"  [ok]  jniLib  {abi}/{so_name}  {human_size(so_path.stat().st_size)}")
            else:
                print(f"  [MISS] jniLib  {so_path}")
                missing += 1

    if missing:
        print()
        print(f"[ERR] 缺 {missing} 个资产。补全方式：")
        print("  - rootfs:   把 debian-13-<arm64|armhf|amd64>.tar.xz 放到 app/assets/rootfs/")
        print("  - jniLibs:  把 6 个 .so 按 ABI 放到 app/android/app/src/main/jniLibs/<abi>/")
        print("              (libbash.so / libbusybox.so / libproot.so / libsudo.so /")
        print("               libloader.so / liblibtalloc.so.2.so)")
    return missing


def main() -> int:
    parser = argparse.ArgumentParser(description="MoFox-Android 一键打包")
    parser.add_argument("--release", action="store_true", help="构建 release APK (未签名)")
    parser.add_argument("--clean", action="store_true", help="构建前 flutter clean")
    parser.add_argument("--no-pub-get", action="store_true", help="跳过 flutter pub get")
    parser.add_argument("--split-per-abi", action="store_true", help="按 ABI 拆分 APK")
    parser.add_argument("--target-platform", help="传给 flutter build apk 的目标平台，例如 android-arm64")
    parser.add_argument("--artifact-label", help="追加到 dist APK 文件名中的标签，例如 arm64-v8a")
    parser.add_argument("--check-assets", action="store_true", help="只跑资产预检然后退出")
    parser.add_argument("--skip-asset-check", action="store_true", help="跳过资产预检 (调试用)")
    parser.add_argument(
        "--fetch-rootfs",
        action="store_true",
        help="构建前下载缺失的 Debian 13 (trixie) rootfs",
    )
    parser.add_argument(
        "--fetch-rootfs-only",
        action="store_true",
        help="只下载 rootfs 然后退出，不构建",
    )
    parser.add_argument(
        "--force-fetch-rootfs",
        action="store_true",
        help="强制重新下载，即使 .tar.xz 已存在",
    )
    args = parser.parse_args()

    if not APP_DIR.exists():
        print(f"[ERR] 找不到 Flutter 工程目录: {APP_DIR}", file=sys.stderr)
        return 1

    if args.target_platform:
        if args.target_platform not in TARGET_PLATFORM_TO_ABI:
            print(
                f"[ERR] 不支持的 --target-platform: {args.target_platform}\n"
                f"      仅支持: {', '.join(TARGET_PLATFORM_TO_ABI)}",
                file=sys.stderr,
            )
            return 1
        abis = [TARGET_PLATFORM_TO_ABI[args.target_platform]]
    else:
        abis = list(ABIS)

    if args.fetch_rootfs or args.fetch_rootfs_only:
        rc = fetch_rootfs(abis, force=args.force_fetch_rootfs)
        if rc != 0:
            return rc
        if args.fetch_rootfs_only:
            print("[INFO] --fetch-rootfs-only 完成。")
            return 0

    if not args.skip_asset_check:
        missing = check_assets(abis)
        if missing:
            return 2
    if args.check_assets:
        print("[INFO] --check-assets 完成。")
        return 0

    flutter = find_flutter()
    print(f"[INFO] 使用 flutter: {flutter}")

    flavor = "release" if args.release else "debug"
    started = time.time()

    if args.clean:
        rc = stream_run([flutter, "clean"], cwd=APP_DIR)
        if rc != 0:
            print(f"[ERR] flutter clean 失败 (exit={rc})", file=sys.stderr)
            return rc

    if not args.no_pub_get:
        rc = stream_run([flutter, "pub", "get"], cwd=APP_DIR)
        if rc != 0:
            print(f"[ERR] flutter pub get 失败 (exit={rc})", file=sys.stderr)
            return rc

    build_cmd = [flutter, "build", "apk", f"--{flavor}"]
    if args.split_per_abi:
        build_cmd.append("--split-per-abi")
    if args.target_platform:
        build_cmd.extend(["--target-platform", args.target_platform])
    rc = stream_run(build_cmd, cwd=APP_DIR)
    if rc != 0:
        print(f"[ERR] flutter build apk --{flavor} 失败 (exit={rc})", file=sys.stderr)
        return rc

    apk_dir = APP_DIR / "build" / "app" / "outputs" / "flutter-apk"
    if not apk_dir.exists():
        print(f"[ERR] 找不到 APK 输出目录: {apk_dir}", file=sys.stderr)
        return 2

    apks = sorted(apk_dir.glob(f"app-{flavor}*.apk"))
    if not apks:
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
