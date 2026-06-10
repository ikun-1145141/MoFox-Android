import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/runtime/runtime_bridge.dart';

const String _oobeDoneKey = 'oobe_done';

/// 是否已完成 OOBE。
///
/// 旧版本可能已经完成 rootfs/bootstrap，但还没可靠写入 `oobe_done`。
/// 启动时用原生 runtime 事实状态兜底，并把结果补写回 SharedPreferences。
final oobeStatusProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_oobeDoneKey) == true) return true;

  final bootstrapped = await ref.read(runtimeBridgeProvider).isBootstrapped();
  if (bootstrapped) {
    await prefs.setBool(_oobeDoneKey, true);
    return true;
  }
  return false;
});

/// 标记 OOBE 完成；最后一步成功后调一次。
Future<void> markOobeDone(WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_oobeDoneKey, true);
  ref.invalidate(oobeStatusProvider);
}
