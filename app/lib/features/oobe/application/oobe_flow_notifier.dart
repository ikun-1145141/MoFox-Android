import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/oobe_step.dart';

class OobeFlowState {
  const OobeFlowState({
    required this.current,
    required this.result,
  });

  final OobeStep current;
  final OobeStepResult result;

  OobeFlowState copyWith({OobeStep? current, OobeStepResult? result}) =>
      OobeFlowState(
        current: current ?? this.current,
        result: result ?? this.result,
      );

  static const OobeFlowState initial = OobeFlowState(
    current: OobeStep.welcome,
    result: OobeStepPending(),
  );
}

/// 驱动 OOBE 各步的中央 Notifier。具体每一步的执行细节由对应页面注入回调，
/// Notifier 这里只管「当前是谁 / 进度如何 / 失败回退」。
class OobeFlowNotifier extends Notifier<OobeFlowState> {
  @override
  OobeFlowState build() => OobeFlowState.initial;

  void start() {
    state = state.copyWith(result: const OobeStepRunning('准备中…'));
  }

  void progress(String message) {
    state = state.copyWith(result: OobeStepRunning(message));
  }

  void completeStep() {
    final next = state.current.next();
    state = OobeFlowState(
      current: next,
      result: next == OobeStep.done
          ? const OobeStepSuccess()
          : const OobeStepPending(),
    );
  }

  void fail(String message, {bool recoverable = true}) {
    state = state.copyWith(
      result: OobeStepFailure(message, recoverable: recoverable),
    );
  }

  void retry() {
    state = state.copyWith(result: const OobeStepPending());
  }

  void jumpTo(OobeStep step) {
    state = OobeFlowState(current: step, result: const OobeStepPending());
  }
}

final oobeFlowProvider =
    NotifierProvider<OobeFlowNotifier, OobeFlowState>(OobeFlowNotifier.new);
