# 内嵌运行时资源

`bootstrap-<abi>.zip` 与 `bootstrap.sha256` 由 CI / nightly 流程在打包前下载并放到这里：

- `bootstrap-aarch64.zip`
- `bootstrap-arm.zip`（可选，看是否覆盖 32 位）
- `bootstrap-x86_64.zip`（模拟器调试用）
- `bootstrap.sha256`：每行 `<sha256>  bootstrap-<abi>.zip`

当前 pin 到 [termux/termux-packages bootstrap-2026.06.07-r1+apt.android-7](https://github.com/termux/termux-packages/releases/tag/bootstrap-2026.06.07-r1%2Bapt.android-7) 中的 `bootstrap-*.zip`。

> 大文件不入仓。CI 按 ABI 分开下载并构建 APK，避免单个 APK 内置无用架构的 bootstrap。
