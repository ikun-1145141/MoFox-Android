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

## 内嵌 Termux runtime

`app/assets/runtime/bootstrap-*.zip` 不入仓，由 CI / nightly 在构建前从
[termux/termux-packages releases](https://github.com/termux/termux-packages/releases) 按 ABI 下载并校验 SHA-256。
本地手动构建 APK 时也需要先把对应架构的 bootstrap zip 放进 `app/assets/runtime/`，否则 OOBE 运行时安装步骤会缺资产。

## 许可

本项目采用 GNU Affero General Public License v3.0（AGPL-3.0），详见 [LICENSE](LICENSE)。内嵌的 Termux bootstrap 沿用其上游 GPLv3 / 各包原 LICENSE。
