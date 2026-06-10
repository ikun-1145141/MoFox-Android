import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/runtime/runtime_bridge.dart';
import '../domain/system_stats.dart';

final systemStatsProvider =
    StreamProvider.autoDispose<SystemStats>((ref) async* {
  final runtime = ref.watch(runtimeBridgeProvider);
  yield await runtime.systemStats();
  yield* Stream<void>.periodic(const Duration(seconds: 5))
      .asyncMap((_) => runtime.systemStats());
});
