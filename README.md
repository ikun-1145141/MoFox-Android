# MoFox-Android

[Neo-MoFox](https://github.com/MoFox-Studio/Neo-MoFox) 的安卓原生外壳 App。自带完整 Linux 运行时（proot + Debian 13），不依赖 Termux，安装即可用。原生层负责 OOBE、实例管理、内嵌运行时、终端、保活与系统级设置。

> 完整架构请看 [ARCHITECTURE.md](ARCHITECTURE.md)。
> 使用 App 部署请看 [Neo-MoFox Android 官方部署指南（Beta）](docs/android-deployment-guide.md)。

## 功能

- **OOBE 一次性引导**：欢迎 → 系统体检 → 解压 rootfs → 保活授权，四步完成。
- **实例管理**：支持创建多个 Bot 实例，每个实例独立目录（`/root/instances/<id>/`），可启停、续装、查看日志。
- **实例创建向导**：镜像源检测 → EULA → 实例信息 → 账号 → 模型 → 网络 → 摘要 → 安装，八步表单 + 彩色安装日志。
- **首页概览**：CPU / 内存 / 存储使用率，主图模式（沉浸 / 紧凑 / 隐藏）。
- **彩色终端**：xterm.dart + flutter_pty 直连 Debian bash，固定深色主题 + .bashrc 注入彩色 prompt。
- **WebUI 壳**：Neo-MoFox WebUI 与 NapCat 控制台切换。
- **外观设置**：主题模式（跟随系统 / 浅色 / 深色）、Android 12+ 动态取色、主图模式。
- **保活体检**：通知权限、电池白名单、前台服务、开机自启、厂商自启动一键检查与跳转。
- **App 日志**：双路输出（控制台 + 文件），支持导出分享，方便排查问题。
- **NapCat 扫码登录**：实例详情页内弹出二维码，QQ 扫码即登录。

## 仓库结构

```
MoFox-Android/
├── ARCHITECTURE.md        # 架构总览（单一真实文档）
├── tools/build.py         # 构建脚本
└── app/                   # Flutter 工程
    ├── lib/               # Dart 源码（Clean Architecture × Feature-First）
    │   ├── main.dart      # 入口（runZonedGuarded + 日志）
    │   ├── app/           # MaterialApp.router + GoRouter
    │   ├── core/          # runtime / platform / theme / ui / utils
    │   └── features/      # oobe / wizard / home / dashboard / instance / shell / webview / terminal / settings
    ├── android/           # 原生 Android 工程（Kotlin + jniLibs）
    │   └── app/src/main/jniLibs/<abi>/    # 原生二进制（不入仓）
    ├── assets/
    │   ├── rootfs/        # Debian 13 (trixie) rootfs（不入仓）
    │   ├── scripts/       # 注入到 rootfs 的初始化脚本
    │   ├── legal/         # EULA / 隐私协议
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

### 2. Debian 13 (trixie) rootfs

```
app/assets/rootfs/
├── debian-13-arm64-v8a.tar.xz
├── debian-13-armeabi-v7a.tar.xz
└── debian-13-x86_64.tar.xz
```

> rootfs 来源：[LXC images](https://images.linuxcontainers.org/) 的 `debian/trixie/<arch>/default/` 每日构建。`python tools/build.py --fetch-rootfs` 会自动列目录抓最新时间戳并下载，按优先级走清华 → BFSU → 上游官方三个镜像。

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
# Invoke-WebRequest -Uri "<release-url>/debian-13-arm64-v8a.tar.xz" -OutFile "app/assets/rootfs/debian-13-arm64-v8a.tar.xz"

# 3. 构建
python tools/build.py --target-platform android-arm64 --artifact-label arm64-v8a
```

多 ABI 调试时把对应 ABI 的 jniLibs + rootfs 都准备好，再用不同 `--target-platform` 分别打包。

## CI / Nightly

- **PR**：`flutter pub get` + `flutter analyze --no-fatal-infos` + `flutter test`，**不构建 APK，不下载运行时**。
- **Push**：按当前支持的 `arm64-v8a` 拉取 jniLibs + rootfs，构建 debug APK 上传 artifact。
- **Nightly**：每天北京时间 02:00 构建 `arm64-v8a` APK；手动触发可选 `debug` / `release`，定时和手动构建都会重建 `nightly` 预发布。

## 常见构建问题

- `Missing runtime asset: jniLibs/<abi>/libproot.so` 或 `assets/rootfs/debian-13-*.tar.xz`：本地 APK 没带运行时资产。按上面"本地手动准备运行时资产"准备齐全后重建。
- 真机首启卡在 `安装系统依赖` / `apt install`：通常是设备网络或镜像源问题。OOBE 内置镜像源切换（清华 / 中科大 / 阿里 / 官方），可在向导日志页或设置内切换重试。
- 真机首启卡在 `安装 NapCat`：NapCat 走 GitHub 原始链接，国内可能慢。OOBE 内置多个 GitHub 加速代理自动测延迟。
- `找不到 flutter`：确认 Flutter 已加入 `PATH`，或安装 / 配置 `fvm` 的默认版本。脚本也会尝试 `~/fvm/default/bin/flutter(.bat)`。
- Release APK 默认未签名；正式分发前需要按 Android 签名流程配置 keystore。

## 许可

本项目采用 GNU Affero General Public License v3.0（AGPL-3.0），详见 [LICENSE](LICENSE)。内嵌的 proot / busybox / bash / sudo / talloc 等原生二进制沿用其上游 LICENSE（GPLv2/v3），Debian 13 (trixie) rootfs 沿用 Debian 各组件原 LICENSE。
