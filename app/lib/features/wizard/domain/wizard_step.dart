/// Wizard 配置阶段（用户填表）。
enum WizardStep {
  instanceInfo, // 1. 实例名称
  account, // 2. Bot QQ + 昵称 + 主人 QQ
  model, // 3. API Key + Base URL
  network, // 4. WS 端口 + 通道 + WebUI Key
  components, // 5. 装 NapCat / 装 WebUI
  summary, // 6. 摘要确认
  install; // 7. 执行安装

  WizardStep? next() {
    const values = WizardStep.values;
    final i = values.indexOf(this);
    return i + 1 < values.length ? values[i + 1] : null;
  }

  WizardStep? prev() {
    const values = WizardStep.values;
    final i = values.indexOf(this);
    return i > 0 ? values[i - 1] : null;
  }

  String get title => switch (this) {
        WizardStep.instanceInfo => '实例信息',
        WizardStep.account => '账号配置',
        WizardStep.model => '模型配置',
        WizardStep.network => '网络配置',
        WizardStep.components => '组件选择',
        WizardStep.summary => '确认摘要',
        WizardStep.install => '安装执行',
      };

  String get description => switch (this) {
        WizardStep.instanceInfo => '为你的 Bot 实例命名',
        WizardStep.account => '配置 Bot 的 QQ 账号信息',
        WizardStep.model => '配置大语言模型 API',
        WizardStep.network => '配置端口、通道与 WebUI 密钥',
        WizardStep.components => '选择要安装的可选组件',
        WizardStep.summary => '请确认以下配置信息',
        WizardStep.install => '正在执行安装，请稍候',
      };
}

/// Wizard 表单的累积数据。
class InstanceDraft {
  const InstanceDraft({
    this.name = '',
    this.botQq = '',
    this.botNickname = '',
    this.ownerQq = '',
    this.apiKey = '',
    this.apiBaseUrl = 'https://api.openai.com/v1',
    this.wsPort = 8095,
    this.channel = 'main',
    this.webuiApiKey = '',
    this.installNapcat = true,
    this.installWebui = true,
  });

  final String name;
  final String botQq;
  final String botNickname;
  final String ownerQq;
  final String apiKey;
  final String apiBaseUrl;
  final int wsPort;
  final String channel;
  final String webuiApiKey;
  final bool installNapcat;
  final bool installWebui;

  InstanceDraft copyWith({
    String? name,
    String? botQq,
    String? botNickname,
    String? ownerQq,
    String? apiKey,
    String? apiBaseUrl,
    int? wsPort,
    String? channel,
    String? webuiApiKey,
    bool? installNapcat,
    bool? installWebui,
  }) =>
      InstanceDraft(
        name: name ?? this.name,
        botQq: botQq ?? this.botQq,
        botNickname: botNickname ?? this.botNickname,
        ownerQq: ownerQq ?? this.ownerQq,
        apiKey: apiKey ?? this.apiKey,
        apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
        wsPort: wsPort ?? this.wsPort,
        channel: channel ?? this.channel,
        webuiApiKey: webuiApiKey ?? this.webuiApiKey,
        installNapcat: installNapcat ?? this.installNapcat,
        installWebui: installWebui ?? this.installWebui,
      );
}

/// 安装执行的子任务（对照桌面端 wizard step 10 的 install-step-item）。
enum InstallTask {
  extractRootfs, // 解压 rootfs（Android 独有）
  installRuntimeDeps, // python / git / uv
  cloneRepo, // git clone Neo-MoFox
  syncDeps, // uv sync
  genConfig, // 生成默认 toml
  writeCore, // 写 core.toml
  writeModel, // 写 model.toml
  writeAdapter, // 写 adapter.toml
  installWebui, // 装 WebUI
  installNapcat, // 装 Napcat
  napcatLogin, // Napcat 扫码（弹 BottomSheet）
  writeNapcatConfig, // 写 onebot11
  registerInstance; // 写实例到本地仓库

  String get label => switch (this) {
        InstallTask.extractRootfs => '解压运行时',
        InstallTask.installRuntimeDeps => '安装系统依赖',
        InstallTask.cloneRepo => '克隆 Neo-MoFox 仓库',
        InstallTask.syncDeps => '同步 Python 依赖',
        InstallTask.genConfig => '生成默认配置',
        InstallTask.writeCore => '写入 core.toml',
        InstallTask.writeModel => '写入 model.toml',
        InstallTask.writeAdapter => '写入 adapter.toml',
        InstallTask.installWebui => '安装 WebUI',
        InstallTask.installNapcat => '安装 NapCat',
        InstallTask.napcatLogin => 'NapCat 扫码登录',
        InstallTask.writeNapcatConfig => '写入 NapCat 配置',
        InstallTask.registerInstance => '注册实例',
      };
}

enum InstallTaskStatus { pending, running, success, failed, skipped }
