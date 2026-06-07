/// OOBE 9 步状态机的步骤枚举。
///
/// 每一步对应 ARCHITECTURE.md §5.1 中的一个幂等子任务，
/// 顺序与文档保持一致。
enum OobeStep {
  welcome, // 1. 欢迎 + EULA
  systemCheck, // 2. 系统体检（ABI / 空间 / 内存）
  extractRootfs, // 3. 解压内嵌 Termux rootfs
  keepalivePerm, // 4. 保活授权引导
  installRuntimeDeps, // 5. 装 python / git / uv
  napcatLogin, // 6. 安装 Napcat + 扫码登录
  fetchNeoMofox, // 7. git clone + uv sync
  generateConfig, // 8. 首跑生成默认 toml
  fillFormAndStart, // 9. 表单填写 + 启动 Bot
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
