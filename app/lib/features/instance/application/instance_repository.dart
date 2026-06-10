import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/instance.dart';

// v2: 加入了 installDir，支持每个 bot 装到独立目录。旧 v1 数据没有这个字段，
// 直接抛弃即可（OOBE 已完成的老用户极少，且 fromJson 也会回退到默认值）。
const String _kInstancesKey = 'instances_v2';

/// 实例仓储（单设备本地存储）。
///
/// 起步用 SharedPreferences 存 JSON 数组，后续如果数据多/查询复杂再换 drift。
class InstanceRepository {
  InstanceRepository(this._prefs);
  final SharedPreferences _prefs;

  List<Instance> loadAll() {
    final raw = _prefs.getString(_kInstancesKey);
    if (raw == null || raw.isEmpty) return <Instance>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => Instance.fromJson(e as Map<String, Object?>))
        .toList(growable: false);
  }

  Future<void> saveAll(List<Instance> items) async {
    final encoded = jsonEncode(items.map((i) => i.toJson()).toList());
    await _prefs.setString(_kInstancesKey, encoded);
  }

  Future<void> add(Instance instance) async {
    final list = loadAll().toList()..add(instance);
    await saveAll(list);
  }

  Future<void> remove(String id) async {
    final list = loadAll().where((i) => i.id != id).toList();
    await saveAll(list);
  }
}

final instanceRepositoryProvider =
    FutureProvider<InstanceRepository>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return InstanceRepository(prefs);
});

/// 当前所有实例（同步快照 + 修改时手动 invalidate）。
final instancesProvider = FutureProvider<List<Instance>>((ref) async {
  final repo = await ref.watch(instanceRepositoryProvider.future);
  return repo.loadAll();
});
