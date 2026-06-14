# MoFox-Android

[Neo-MoFox](https://github.com/MoFox-Studio/Neo-MoFox) 的安卓原生外壳 App。**WebView 套自家 WebUI** 做主界面，原生层只负责 OOBE、内嵌 Linux 运行时、终端、保活与系统级设置。

> 完整架构请看 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 仓库结构

```
MoFox-Android/
├── ARCHITECTURE.md        # 架构总览（单一真实文档）
├── tools/build.py         # 构建脚本
└── app/                   # Flutter 工程
    ├── lib/               # Dart 源码（Clean Architecture × Feature-First）
    ├── android/           # 原生 Android 工程（Kotlin + jniLibs）
    │   └── app/src/main/jniLibs/<abi>/    # 原生二进制（不入仓）
    ├── assets/
    │   ├── rootfs/        # Ubuntu 26.04 rootfs（不入仓）
    │   ├── scripts/       # 注入到 rootfs 的初始化脚本
    │   └── icons/
    └── test/              # 单元 / Widget / 集成测试
```

## 开发环境

- Flutter 3.22+ / Dart 3.4+
- Android SDK Platform 35 + NDK 27
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

## 内嵌 Linux runtime

App 不依赖 Termux，自带完整运行时。运行时由两部分组成，**都不入仓**，由 CI 在构建前下载：

### 1. 原生二进制（jniLibs 投递）

Android 把 `src/main/jniLibs/<abi>/lib*.so` 解包到 `nativeLibraryDir`，该目录是少数 W^X 默认豁免的可执行路径。利用这点把 6 个原生二进制伪装成 `.so` 投递：

| jniLibs 文件名 | 实际作用 |
| --- | --- |
| `libbash.so`           | bash 解释器 |
| `libbusybox.so`        | BusyBox 工具集 |
| `libproot.so`          | proot rootless 容器 |
| `libsudo.so`           | proot 内的 sudo 替身（**严禁 strip**） |
| `libloader.so`         | proot 的 ELF loader |
| `liblibtalloc.so.2.so` | proot 依赖的 talloc.so.2 |

放置位置：

```
app/android/app/src/main/jniLibs/
├── arm64-v8a/
│   ├── libbash.so
│   ├── libbusybox.so
│   ├── libproot.so
│   ├── libsudo.so
│   ├── libloader.so
│   └── liblibtalloc.so.2.so
├── armeabi-v7a/...
└── x86_64/...
```

### 2. Ubuntu 26.04 rootfs

```
app/assets/rootfs/
├── ubuntu-26.04-arm64-v8a.tar.xz
├── ubuntu-26.04-armeabi-v7a.tar.xz
└── ubuntu-26.04-x86_64.tar.xz
```

> Ubuntu 26.04 LTS 正式发布前，初期使用 24.04 LTS (noble) 兜底，**文件名保持 `ubuntu-26.04-*` 占位**，正式发布后仅替换产物，架构无需改动。

### 本地手动准备运行时资产

只构建 arm64 真机包时：

```pwsh
# 1. 下载 jniLibs（6 个 .so）
$jniDir = "app/android/app/src/main/jniLibs/arm64-v8a"
New-Item -ItemType Directory -Force -Path $jniDir | Out-Null
# 从 GitHub Release 拉取（占位 URL，实际地址以 CI 配置为准）
# Invoke-WebRequest -Uri "<release-url>/arm64-v8a/libbash.so" -OutFile "$jniDir/libbash.so"
# ... 其余 5 个同理

# 2. 下载 rootfs
New-Item -ItemType Directory -Force -Path "app/assets/rootfs" | Out-Null
# Invoke-WebRequest -Uri "<release-url>/ubuntu-26.04-arm64-v8a.tar.xz" -OutFile "app/assets/rootfs/ubuntu-26.04-arm64-v8a.tar.xz"

# 3. 构建
python tools/build.py --target-platform android-arm64 --artifact-label arm64-v8a
```

多 ABI 调试时把对应 ABI 的 jniLibs + rootfs 都准备好，再用不同 `--target-platform` 分别打包。

## CI / Nightly

- **PR**：`flutter pub get` + `flutter analyze --no-fatal-infos` + `flutter test`，**不构建 APK，不下载运行时**。
- **Push**：按当前支持的 `arm64-v8a` 拉取 jniLibs + rootfs，构建 debug APK 上传 artifact。
- **Nightly**：每天北京时间 02:00 构建 `arm64-v8a` APK；手动触发可选 `debug` / `release`，定时和手动构建都会重建 `nightly` 预发布。

## 常见构建问题

- `Missing runtime asset: jniLibs/<abi>/libproot.so` 或 `assets/rootfs/ubuntu-*.tar.xz`：本地 APK 没带运行时资产。按上面"本地手动准备运行时资产"准备齐全后重建。
- 真机首启卡在 `安装系统依赖` / `apt install`：通常是设备网络或镜像源问题。OOBE 内置镜像源切换（清华 / 中科大 / 阿里 / 官方），可在向导日志页或设置内切换重试。
- 真机首启卡在 `安装 NapCat`：NapCat 走 GitHub 原始链接，国内可能慢。OOBE 内置多个 GitHub 加速代理自动测延迟。
- `找不到 flutter`：确认 Flutter 已加入 `PATH`，或安装 / 配置 `fvm` 的默认版本。脚本也会尝试 `~/fvm/default/bin/flutter(.bat)`。
- Release APK 默认未签名；正式分发前需要按 Android 签名流程配置 keystore。

## 许可

本项目采用 GNU Affero General Public License v3.0（AGPL-3.0），详见 [LICENSE](LICENSE)。内嵌的 proot / busybox / bash / sudo / talloc 等原生二进制沿用其上游 LICENSE（GPLv2/v3），Ubuntu 26.04 rootfs 沿用 Canonical 各组件原 LICENSE。
