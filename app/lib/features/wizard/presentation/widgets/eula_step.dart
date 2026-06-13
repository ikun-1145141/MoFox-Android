import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/wizard_notifier.dart';
import '../../domain/wizard_mirror_source.dart';

/// EULA 许可协议查看步骤。
///
/// 参照 Neo-MoFox 桌面启动器的 welcome 步骤，
/// 从远程仓库获取协议文本，用户必须勾选同意后才能继续下一步。
class EulaStep extends ConsumerStatefulWidget {
  const EulaStep({super.key});

  @override
  ConsumerState<EulaStep> createState() => _EulaStepState();
}

class _EulaStepState extends ConsumerState<EulaStep> {
  late Future<_EulaDocument> _documentFuture;

  @override
  void initState() {
    super.initState();
    _documentFuture = _fetchEula();
  }

  Future<_EulaDocument> _fetchEula() async {
    final source = wizardMirrorSourceFor(
      ref.read(wizardProvider).draft.mirrorId,
    );
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        responseType: ResponseType.plain,
      ),
    );
    try {
      final response = await dio.get<String>(source.eulaUrl);
      final body = response.data?.trim();
      if (response.statusCode == 200 && body != null && body.isNotEmpty) {
        return _EulaDocument(source: source, content: body);
      }
    } catch (_) {
      throw StateError('无法从 ${source.name} 获取 EULA，请检查网络后重试。');
    }
    throw StateError('无法从 ${source.name} 获取 EULA，请检查网络后重试。');
  }

  void _retry() {
    setState(() => _documentFuture = _fetchEula());
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(wizardProvider).draft;
    final notifier = ref.read(wizardProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 协议内容区域
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: FutureBuilder<_EulaDocument>(
                  future: _documentFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError || snapshot.data == null) {
                      return _EulaErrorView(onRetry: _retry);
                    }
                    return _EulaContent(document: snapshot.data!);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 同意勾选
          Material(
            color: draft.eulaAccepted
                ? scheme.primaryContainer.withValues(alpha: 0.3)
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => notifier.update(
                (d) => d.copyWith(eulaAccepted: !d.eulaAccepted),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: <Widget>[
                    Checkbox(
                      value: draft.eulaAccepted,
                      onChanged: (v) => notifier.update(
                        (d) => d.copyWith(eulaAccepted: v ?? false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '我已阅读并同意上述用户许可协议',
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EulaContent extends StatelessWidget {
  const _EulaContent({required this.document});

  final _EulaDocument document;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Neo-MoFox 用户许可协议',
            style: text.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '镜像源：${document.source.name}',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          SelectableText(
            document.content,
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _EulaErrorView extends StatelessWidget {
  const _EulaErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.cloud_off_outlined, color: scheme.error, size: 36),
            const SizedBox(height: 12),
            Text(
              'EULA 获取失败',
              style: text.titleMedium?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请检查网络连接后重试。协议未加载成功前不建议继续。',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重新获取'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EulaDocument {
  const _EulaDocument({required this.source, required this.content});

  final WizardMirrorSource source;
  final String content;
}
