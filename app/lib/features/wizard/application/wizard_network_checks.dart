import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/wizard_mirror_source.dart';
import 'wizard_notifier.dart';

class MirrorProbeResult {
  const MirrorProbeResult({
    required this.mirror,
    required this.reachable,
    required this.latencyMs,
    this.errorMessage,
  });

  final WizardMirrorSource mirror;
  final bool reachable;
  final int latencyMs;
  final String? errorMessage;
}

class MirrorCheckState {
  const MirrorCheckState({
    required this.running,
    required this.completed,
    required this.results,
  });

  final bool running;
  final bool completed;
  final Map<String, MirrorProbeResult> results;

  bool isReachable(String mirrorId) => results[mirrorId]?.reachable == true;
  bool get hasReachable => results.values.any((result) => result.reachable);
}

class EulaDocument {
  const EulaDocument({required this.source, required this.content});

  final WizardMirrorSource source;
  final String content;
}

typedef MirrorProbe = Future<MirrorProbeResult> Function(
  WizardMirrorSource source,
);
typedef EulaLoader = Future<EulaDocument> Function(WizardMirrorSource source);

final _wizardDioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      sendTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      followRedirects: true,
      maxRedirects: 5,
    ),
  );
  ref.onDispose(() => dio.close(force: true));
  return dio;
});

/// 单次探测使用 Git smart-HTTP 的 refs 入口，确认安装时真正要访问的仓库可达。
final mirrorProbeProvider = Provider<MirrorProbe>((ref) {
  final dio = ref.watch(_wizardDioProvider);
  return (source) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await dio
          .get<List<int>>(
            '${source.repoUrl}/info/refs?service=git-upload-pack',
            options: Options(
              responseType: ResponseType.bytes,
              headers: const <String, String>{
                'Accept': 'application/x-git-upload-pack-advertisement',
                'Range': 'bytes=0-2047',
              },
              validateStatus: (status) =>
                  status != null && status >= 200 && status < 400,
            ),
          )
          .timeout(const Duration(seconds: 7));
      stopwatch.stop();
      final reachable = response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 400 &&
          (response.data?.isNotEmpty ?? false);
      return MirrorProbeResult(
        mirror: source,
        reachable: reachable,
        latencyMs: stopwatch.elapsedMilliseconds,
        errorMessage: reachable ? null : '响应为空或状态异常',
      );
    } on Object catch (error) {
      stopwatch.stop();
      return MirrorProbeResult(
        mirror: source,
        reachable: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        errorMessage: _networkErrorText(error),
      );
    }
  };
});

final eulaLoaderProvider = Provider<EulaLoader>((ref) {
  final dio = ref.watch(_wizardDioProvider);
  return (source) async {
    try {
      final response = await dio
          .get<String>(
            source.eulaUrl,
            options: Options(
              responseType: ResponseType.plain,
              validateStatus: (status) =>
                  status != null && status >= 200 && status < 300,
            ),
          )
          .timeout(const Duration(seconds: 9));
      final content = response.data?.trim();
      if (content == null || content.isEmpty) {
        throw const FormatException('服务器返回了空协议');
      }
      return EulaDocument(source: source, content: content);
    } on Object catch (error) {
      throw StateError(
          '无法从 ${source.name} 获取 EULA：${_networkErrorText(error)}');
    }
  };
});

final eulaDocumentProvider =
    FutureProvider.autoDispose.family<EulaDocument, String>((ref, mirrorId) {
  final source = wizardMirrorSourceFor(mirrorId);
  return ref.watch(eulaLoaderProvider)(source);
});

final mirrorCheckProvider =
    NotifierProvider<MirrorCheckNotifier, MirrorCheckState>(
  MirrorCheckNotifier.new,
);

class MirrorCheckNotifier extends Notifier<MirrorCheckState> {
  int _generation = 0;

  @override
  MirrorCheckState build() {
    Future<void>.microtask(run);
    return const MirrorCheckState(
      running: true,
      completed: false,
      results: <String, MirrorProbeResult>{},
    );
  }

  Future<void> run() async {
    final generation = ++_generation;
    state = const MirrorCheckState(
      running: true,
      completed: false,
      results: <String, MirrorProbeResult>{},
    );
    final probe = ref.read(mirrorProbeProvider);
    final results = await Future.wait(wizardMirrorSources.map(probe));
    if (generation != _generation) return;

    final resultMap = <String, MirrorProbeResult>{
      for (final result in results) result.mirror.id: result,
    };
    state = MirrorCheckState(
      running: false,
      completed: true,
      results: resultMap,
    );

    final available = results.where((result) => result.reachable).toList()
      ..sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
    if (available.isNotEmpty) selectMirror(available.first.mirror.id);
  }

  void selectMirror(String mirrorId) {
    if (!state.completed || !state.isReachable(mirrorId)) return;
    final notifier = ref.read(wizardProvider.notifier);
    notifier.update(
      (draft) => draft.copyWith(
        mirrorId: mirrorId,
        eulaAccepted: draft.mirrorId == mirrorId ? draft.eulaAccepted : false,
      ),
    );
  }
}

String _networkErrorText(Object error) {
  if (error is TimeoutException) return '请求超时';
  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        '请求超时',
      DioExceptionType.connectionError => '网络连接失败',
      DioExceptionType.badResponse =>
        '服务器返回 ${error.response?.statusCode ?? '异常状态'}',
      _ => error.message ?? '网络请求失败',
    };
  }
  if (error is FormatException) return error.message;
  return error.toString();
}
