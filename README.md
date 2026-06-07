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

`app/assets/runtime/bootstrap-*.zip` 不入仓，由 `tools/fetch-bootstrap.ps1`（待加）从
[termux/termux-packages releases](https://github.com/termux/termux-packages/releases) 拉取并校验 SHA-256。
首次构建 release 包前必须先跑这个脚本，否则 OOBE 第 3 步会缺资产。

## 许可

GPLv3，详见 [LICENSE](LICENSE)。内嵌的 Termux bootstrap 沿用其上游 GPLv3 / 各包原 LICENSE。
