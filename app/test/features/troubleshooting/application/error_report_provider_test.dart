import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mofox_android/features/troubleshooting/application/error_report_provider.dart';

void main() {
  // errorReportNotifier 是全局单例（appLogger 输出等无 ref 环境直接引用），
  // 不能随 container 销毁：整套测试共用一个容器，用 clear() 隔离用例。
  final container = ProviderContainer();

  List<ErrorReportEntry> entries() => container.read(errorReportProvider);

  setUp(errorReportNotifier.clear);

  test('add 追加条目并脱敏密钥', () {
    errorReportNotifier.add(
      level: ErrorReportLevel.error,
      source: 'SnowLuma',
      message: 'WebUI 上报失败 token=abcdef123456',
    );
    expect(entries(), hasLength(1));
    expect(entries().single.message, contains('[REDACTED]'));
    expect(entries().single.message, isNot(contains('abcdef123456')));
    expect(entries().single.level, ErrorReportLevel.error);
    expect(entries().single.repeat, 1);
  });

  test('相邻同源同文折叠为一条并递增计数', () {
    errorReportNotifier
      ..add(
        level: ErrorReportLevel.diag,
        source: 'SnowLuma',
        message: 'WebUI 未就绪自检: node=缺失',
      )
      ..add(
        level: ErrorReportLevel.diag,
        source: 'SnowLuma',
        message: 'WebUI 未就绪自检: node=缺失',
      )
      ..add(
        level: ErrorReportLevel.diag,
        source: 'SnowLuma',
        message: '另一条不同的诊断行',
      );
    expect(entries(), hasLength(2));
    expect(entries().first.repeat, 2);
    expect(entries().last.repeat, 1);
  });

  test('同文不同源不折叠', () {
    errorReportNotifier
      ..add(level: ErrorReportLevel.error, source: 'Bot', message: '安装失败')
      ..add(
        level: ErrorReportLevel.error,
        source: 'SnowLuma',
        message: '安装失败',
      );
    expect(entries(), hasLength(2));
  });

  test('超过上限丢最旧', () {
    for (var i = 0; i < ErrorReportNotifier.maxEntries + 2; i++) {
      errorReportNotifier.add(
        level: ErrorReportLevel.error,
        source: '应用',
        message: '错误 #$i',
      );
    }
    final kept = entries();
    expect(kept, hasLength(ErrorReportNotifier.maxEntries));
    expect(kept.first.message, '错误 #2');
    expect(kept.last.message, '错误 #${ErrorReportNotifier.maxEntries + 1}');
  });

  test('addProcessLine：SnowLuma [control] 行按 diag 收录', () {
    errorReportNotifier.addProcessLine(
      source: 'SnowLuma',
      line: '[control] OneBot get_status: {"online":false}',
    );
    expect(entries(), hasLength(1));
    expect(entries().single.level, ErrorReportLevel.diag);
  });

  test('addProcessLine：错误模式行优先按 error 收录', () {
    errorReportNotifier.addProcessLine(
      source: 'SnowLuma',
      line: '[control] 快捷登录指令失败: 窗口未找到',
    );
    expect(entries(), hasLength(1));
    expect(entries().single.level, ErrorReportLevel.error);
  });

  test('addProcessLine：SnowLuma 非 [control] 行忽略', () {
    errorReportNotifier.addProcessLine(source: 'SnowLuma', line: '[info] 已启动');
    expect(entries(), isEmpty);
  });

  test('addProcessLine：Bot 普通行忽略、错误行收录', () {
    errorReportNotifier
      ..addProcessLine(source: 'Bot', line: '[plugin] 收到私聊消息')
      ..addProcessLine(
        source: 'Bot',
        line: 'Traceback (most recent call last):',
      );
    expect(entries(), hasLength(1));
    expect(entries().single.level, ErrorReportLevel.error);
  });

  test('addProcessLine：进程退出标记按 error 收录', () {
    errorReportNotifier.addProcessLine(
      source: 'SnowLuma',
      line: '[snowluma] exited with 1',
    );
    expect(entries(), hasLength(1));
    expect(entries().single.level, ErrorReportLevel.error);
  });

  test('clear 清空全部', () {
    errorReportNotifier
      ..add(
        level: ErrorReportLevel.error,
        source: '应用',
        message: '测试',
      )
      ..clear();
    expect(entries(), isEmpty);
  });

  test('buildExportText 包含设备头与条目行', () async {
    errorReportNotifier
      ..add(
        level: ErrorReportLevel.diag,
        source: 'SnowLuma',
        message: '[control] MoFox SnowLuma 脚本构建 20261101-2 (node基线自愈)',
      )
      ..add(
        level: ErrorReportLevel.error,
        source: '应用',
        message: '刷新进程状态失败: boom',
      );
    final text = await errorReportNotifier.buildExportText();
    expect(text, startsWith('MoFox'));
    expect(text, contains('[SnowLuma] [control] MoFox SnowLuma 脚本构建 20261101-2'));
    expect(text, contains('[应用] 刷新进程状态失败: boom'));
  });

  test('buildExportText 折叠行带 ×N 标记', () async {
    errorReportNotifier
      ..add(level: ErrorReportLevel.diag, source: 'SnowLuma', message: '自检')
      ..add(level: ErrorReportLevel.diag, source: 'SnowLuma', message: '自检');
    final text = await errorReportNotifier.buildExportText();
    expect(text, contains('[SnowLuma ×2] 自检'));
  });
}
