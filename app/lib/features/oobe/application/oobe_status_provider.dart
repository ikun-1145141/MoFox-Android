import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _oobeDoneKey = 'oobe_done';

/// 是否已完成 OOBE。
///
/// 只能由 OOBE 最后一页的「开始使用」写入。rootfs 已解压不等于用户已经完成
/// 引导，否则首次启动中途退出后会被误判为已完成。
final oobeStatusProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_oobeDoneKey) ?? false;
});

/// 标记 OOBE 完成；最后一步成功后调一次。
Future<void> markOobeDone(WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_oobeDoneKey, true);
  ref.invalidate(oobeStatusProvider);
}
