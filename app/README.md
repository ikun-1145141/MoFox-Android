# MoFox Android App

Neo-MoFox 的安卓原生外壳 App。应用负责 OOBE、内嵌 proot Linux 运行时、实例创建向导、终端入口、WebUI 外部浏览器跳转与系统级设置。

终端内置 AI 运维助手，可使用用户自备的 OpenAI-compatible 服务进行自然语言排障、解释选中的终端内容并生成结构化操作。助手可通过只读 MCP 实时检索和读取 `docs.mofox-sama.com`；默认副驾驶模式逐项确认并限制自动执行，显式开启 YOLO 后可在应用的 proot 运行时执行任意单行 Shell 命令。

## 安装向导流程

新建实例时，向导按以下顺序执行：

1. 镜像源检测：检测 GitHub 官方源、GHProxy 加速源、Gitee 镜像源，并自动选择延迟最低的可用源。
2. 用户协议：从所选镜像源获取 Neo-MoFox EULA，用户阅读并勾选同意后才能继续。
3. 实例信息：填写实例名称。
4. 账号配置：填写 Bot QQ、昵称和主人 QQ。
5. 模型配置：填写 API Key 与 Base URL。
6. 网络配置：填写 WebSocket 端口、通道和 WebUI Key。
7. 摘要确认：展示用户协议状态、镜像源、实例配置和默认组件。
8. 安装执行：从所选镜像源克隆 Neo-MoFox、同步依赖、生成配置、安装 WebUI、写入 NapCat 配置。

## 可选组件

OOBE 默认只安装 Debian 与基础依赖，不强制下载 NapCat：

- NapCat：OOBE 中可主动勾选；若暂时跳过，首次启动 NapCat 时会自动完成幂等安装与校验。
- WebUI：实例向导中可选择是否安装，用于浏览器中可视化管理 Bot。

实例安装向导会提前写入 NapCat 配置；二维码会在用户启动 NapCat 时展示。

## 断点续装与未完成实例

安装开始时，App 会立即在本地实例仓库登记一个“未完成”实例。若安装失败、异常退出或返回主菜单：

- 管理页会继续显示该未完成实例。
- 安装失败实例会显示失败原因。
- 点击“继续安装”会回到安装执行页，并复用原实例 ID 与安装目录继续安装。
- 安装完成后实例状态会更新为已安装。

## 开发

项目使用 Flutter 与 Riverpod。常用命令：

```bash
flutter pub get
flutter analyze
flutter test
```
