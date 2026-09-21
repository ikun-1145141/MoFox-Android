/// OOBE 5 步：用户 + 设备的一次性引导。
///
/// 实例创建走 `features/wizard`（独立路由），不在 OOBE 里。
/// `extractRuntime` 阶段在 OOBE 里完成全局一次性安装：解压 Debian rootfs、
/// 安装 apt 基础依赖，并按用户选择安装可选的 NapCat。
enum OobeStep {
  welcome, // 1. 欢迎 + EULA
  systemCheck, // 2. 系统体检（ABI / 空间 / 内存）
  extractRuntime, // 3. 解压 rootfs + 装 apt 依赖
  keepalivePerm, // 4. 保活授权引导
  done; // 哨兵：全部完成

  bool get isTerminal => this == OobeStep.done;

  OobeStep next() {
    final values = OobeStep.values;
    final i = values.indexOf(this);
    return i + 1 < values.length ? values[i + 1] : OobeStep.done;
  }
}

/// 首次运行环境准备阶段可执行的原生任务。
enum OobeRuntimeTask {
  extractRootfs('extractRootfs', '解压 Debian 13 rootfs'),
  installRuntimeDeps('installRuntimeDeps', '安装 apt 基础依赖'),
  installNapcat('installNapcat', '安装全局 NapCat'),
  verifyNapcat('verifyNapcat', '复查 NapCat 安装');

  const OobeRuntimeTask(this.nativeName, this.label);

  final String nativeName;
  final String label;
}

/// 生成本次 OOBE 的安装计划。基础环境始终必装，NapCat 只有在用户显式选择后
/// 才会进入计划。
List<OobeRuntimeTask> oobeRuntimeTasks({required bool installNapcat}) =>
    <OobeRuntimeTask>[
      OobeRuntimeTask.extractRootfs,
      OobeRuntimeTask.installRuntimeDeps,
      if (installNapcat) ...<OobeRuntimeTask>[
        OobeRuntimeTask.installNapcat,
        OobeRuntimeTask.verifyNapcat,
      ],
    ];

/// 单步执行结果。
sealed class OobeStepResult {
  const OobeStepResult();
}

class OobeStepPending extends OobeStepResult {
  const OobeStepPending();
}

class OobeStepRunning extends OobeStepResult {
  const OobeStepRunning(this.message);
  final String message;
}

class OobeStepSuccess extends OobeStepResult {
  const OobeStepSuccess();
}

class OobeStepFailure extends OobeStepResult {
  const OobeStepFailure(this.message, {this.recoverable = true});
  final String message;
  final bool recoverable;
}
