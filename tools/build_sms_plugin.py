#!/usr/bin/env python3
"""把 plugins-src/<name> 打包成 Neo-MoFox 的 .mfp 插件包（本质为 ZIP）。

用法（仓库根目录执行）：
    python tools/build_sms_plugin.py                    # 打包全部插件
    python tools/build_sms_plugin.py mofox_sms_bridge   # 只打包指定插件

产物落到 app/assets/plugins/<name>-<version>.mfp，随 APK 铺发链路分发。
打包内容与 mfp 标准一致：manifest.json + 插件源码，排除 __pycache__。
"""

from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SRC_ROOT = REPO_ROOT / "plugins-src"
OUT_DIR = REPO_ROOT / "app" / "assets" / "plugins"
EXCLUDE_DIRS = {"__pycache__", ".git"}
EXCLUDE_FILES = {".DS_Store"}


def build(plugin_dir: Path) -> Path:
    manifest_path = plugin_dir / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    name = manifest["name"]
    version = manifest["version"]
    out_path = OUT_DIR / f"{name}-{version}.mfp"

    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for file in sorted(plugin_dir.rglob("*")):
            if not file.is_file():
                continue
            if any(part in EXCLUDE_DIRS for part in file.parts):
                continue
            if file.name in EXCLUDE_FILES:
                continue
            arcname = file.relative_to(plugin_dir).as_posix()
            zf.write(file, arcname)
    return out_path


def main(argv: list[str]) -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    targets = (
        [SRC_ROOT / name for name in argv]
        if argv
        else [p for p in sorted(SRC_ROOT.iterdir()) if p.is_dir()]
    )
    failures = 0
    for plugin_dir in targets:
        if not (plugin_dir / "manifest.json").is_file():
            print(f"[跳过] {plugin_dir.name}：缺少 manifest.json")
            continue
        try:
            out = build(plugin_dir)
            size_kb = out.stat().st_size / 1024
            print(f"[完成] {out.relative_to(REPO_ROOT)} ({size_kb:.1f} KB)")
        except Exception as exc:  # noqa: BLE001
            failures += 1
            print(f"[失败] {plugin_dir.name}：{exc}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
