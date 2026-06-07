import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 是否已完成 OOBE。`null` 时表示尚未读取，路由层把它视为「未完成」。
final oobeStatusProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('oobe_done') ?? false;
});

/// 标记 OOBE 完成；最后一步成功后调一次。
Future<void> markOobeDone(WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('oobe_done', true);
  ref.invalidate(oobeStatusProvider);
}
