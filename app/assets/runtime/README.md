# 内嵌运行时资源

`bootstrap-<abi>.zip` 与 `bootstrap.sha256` 由 release 流程在打包前生成并放到这里：

- `bootstrap-aarch64.zip`
- `bootstrap-arm.zip`（可选，看是否覆盖 32 位）
- `bootstrap-x86_64.zip`（模拟器调试用）
- `bootstrap.sha256`：每行 `<sha256>  bootstrap-<abi>.zip`

源头：[termux/termux-packages releases](https://github.com/termux/termux-packages/releases) 中的 `bootstrap-*.zip`。

> 大文件不入仓。`tools/fetch-bootstrap.ps1`（待补）会下载并校验。
