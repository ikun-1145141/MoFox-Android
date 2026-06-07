/// Bot / Napcat 的进程三态机。`http_router` 健康检查通过即升 `running`。
enum ProcessState { stopped, starting, running, restarting }

extension ProcessStateLabel on ProcessState {
  String get label => switch (this) {
        ProcessState.stopped => '已停止',
        ProcessState.starting => '启动中',
        ProcessState.running => '运行中',
        ProcessState.restarting => '重启中',
      };
}
