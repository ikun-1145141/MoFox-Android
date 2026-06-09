# MoFox-Android

Neo-MoFox 的安卓原生外壳 App。**WebView 套自家 WebUI** 做主界面，原生层只负责 OOBE、内嵌 Termux 运行时、终端、保活与系统级设置。

> 完整架构请看 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 仓库结构

```
MoFox-Android/
├── ARCHITECTURE.md        # 架构总览（源真实文档）
├── MoFox-Bot-Docs/        # Neo-MoFox 主程序文档
└── app/                   # Flutter 工程
    ├── lib/               # Dart 源码（Clean Architecture × Feature-First）
    ├── android/           # 原生 Android 工程（Kotlin + JNI）
    ├── assets/            # 内嵌 Termux runtime / 脚本 / 图标
    └── test/              # 单元 / Widget / 集成测试
```

## 开发环境

- Flutter 3.22+ / Dart 3.4+
- Android SDK Platform 34 + NDK 27（编 JNI 用）
- JDK 17+（Gradle 8 要求）
- 推荐用 `fvm` 锁版本

```pwsh
cd app
flutter pub get
flutter run                       # 连真机
```

## 本地构建 APK

推荐从仓库根目录使用 `tools/build.py`，脚本会自动寻找 `flutter` / `flutter.bat`，执行 `pub get`，构建 APK，并把产物复制到 `dist/`。

```pwsh
# debug APK
python tools/build.py

# release APK（未签名）
python tools/build.py --release

# 清理后重新构建
python tools/build.py --clean
```

也可以直接使用 Flutter 命令：

```pwsh
cd app
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug
```

debug 产物默认在 `app/build/app/outputs/flutter-apk/app-debug.apk`，脚本复制后的产物在 `dist/`。

## 内嵌 Termux runtime

`app/assets/runtime/bootstrap-*.zip` 不入仓，由 CI / nightly 在构建前从
[termux/termux-packages releases](https://github.com/termux/termux-packages/releases) 按 ABI 下载并校验 SHA-256。
本地手动构建 APK 时也需要先把对应架构的 bootstrap zip 放进 `app/assets/runtime/`，否则 OOBE 运行时安装步骤会缺资产。

当前使用的 Termux bootstrap：

| Android ABI | Flutter target | 文件名 | 下载地址 |
| --- | --- | --- | --- |
| `arm64-v8a` | `android-arm64` | `bootstrap-aarch64.zip` | `https://github.com/termux/termux-packages/releases/download/bootstrap-2026.06.07-r1%2Bapt.android-7/bootstrap-aarch64.zip` |
| `armeabi-v7a` | `android-arm` | `bootstrap-arm.zip` | `https://github.com/termux/termux-packages/releases/download/bootstrap-2026.06.07-r1%2Bapt.android-7/bootstrap-arm.zip` |
| `x86_64` | `android-x64` | `bootstrap-x86_64.zip` | `https://github.com/termux/termux-packages/releases/download/bootstrap-2026.06.07-r1%2Bapt.android-7/bootstrap-x86_64.zip` |

例如只构建 arm64 真机包：

```pwsh
Invoke-WebRequest `
    -Uri "https://github.com/termux/termux-packages/releases/download/bootstrap-2026.06.07-r1%2Bapt.android-7/bootstrap-aarch64.zip" `
    -OutFile "app/assets/runtime/bootstrap-aarch64.zip"

python tools/build.py --target-platform android-arm64 --artifact-label arm64-v8a
```

多 ABI 调试时可以把三个 bootstrap zip 都放进 `app/assets/runtime/`，再用不同的 `--target-platform` 分别打包。`bootstrap.sha256` 只用于 CI / nightly 记录校验结果，本地构建不是必须。

## CI / Nightly

- PR：运行 `flutter pub get`、`flutter analyze --no-fatal-infos`、`flutter test`，不构建 APK。
- Push：按 `arm64-v8a`、`armeabi-v7a`、`x86_64` 三个 ABI 下载对应 Termux bootstrap，并上传 debug APK artifact。
- Nightly：每天北京时间 02:00 构建三 ABI APK；手动触发时可选择 `debug` 或 `release`，定时构建会发布到 `nightly` 预发布。

## 常见构建问题

- `Missing runtime asset bootstrap-*.zip`：本地 APK 没带 Termux bootstrap。下载对应 ABI 的 zip 到 `app/assets/runtime/` 后重建。
- 真机安装运行时卡在 `安装系统依赖`：通常是设备网络、Termux 镜像源、`pkg update` 或 `proot-distro install ubuntu` 下载阶段。请保留安装页实时日志继续排查。
- `找不到 flutter`：确认 Flutter 已加入 `PATH`，或安装 / 配置 `fvm` 的默认版本。脚本也会尝试 `~/fvm/default/bin/flutter(.bat)`。
- Release APK 默认未签名；正式分发前需要按 Android 签名流程配置 keystore。

## 许可

本项目采用 GNU Affero General Public License v3.0（AGPL-3.0），详见 [LICENSE](LICENSE)。内嵌的 Termux bootstrap 沿用其上游 GPLv3 / 各包原 LICENSE。
