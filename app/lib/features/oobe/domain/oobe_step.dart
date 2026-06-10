/// OOBE 5 步：用户 + 设备的一次性引导。
///
/// 实例创建走 `features/wizard`（独立路由），不在 OOBE 里。
/// `extractRuntime` 阶段在 OOBE 里完成全局一次性安装：解压 Debian rootfs、
/// 安装 apt 基础依赖。
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
