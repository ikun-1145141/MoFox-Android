# MoFox Android App

Neo-MoFox 的安卓原生外壳 App。应用负责 OOBE、内嵌 proot Linux 运行时、实例创建向导、终端入口、WebView 与系统级设置。

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

## 默认组件

NapCat 与 WebUI 不再提供选择开关，所有新实例默认安装并配置：

- NapCat：用于 OneBot v11 协议接入和 QQ 扫码登录。
- WebUI：用于浏览器中可视化管理 Bot。

NapCat 二维码会在用户启动 NapCat 时展示，安装向导只负责安装和写入配置。

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
