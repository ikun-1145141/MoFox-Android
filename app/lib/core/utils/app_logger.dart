import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:mofox_android/features/troubleshooting/application/error_report_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 全局日志器；只面向原生壳本身，Bot 业务日志在 WebUI 看。
///
/// 同时输出到控制台和文件（`<appDocDir>/logs/mofox_<date>.log`），
/// 方便事后排查崩溃 / 安装失败 / 进程异常等问题。
final Logger appLogger = Logger(
  filter: _MoFoxLogFilter(),
  printer: PrettyPrinter(
    methodCount: 0,
    lineLength: 100,
    colors: true,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
  output: _MoFoxLogOutput(),
);

/// 在 release 模式下也输出日志（默认 [DevelopmentFilter] 会全屏蔽）。
class _MoFoxLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    return true;
  }
}

/// 多路输出：控制台 + 滚动日志文件。
class _MoFoxLogOutput extends LogOutput {
  IOSink? _fileSink;

  @override
  void output(OutputEvent event) {
    _feedErrorReport(event);
    // 控制台
    for (final line in event.lines) {
      // ignore: avoid_print
      print(line);
    }
    // 文件
    _ensureFileSink().then((sink) {
      if (sink == null) return;
      for (final line in event.lines) {
        sink.writeln(line);
      }
    });
  }

  /// error/warning 级日志进入「报错汇总」（本次启动的内存缓冲）。
  /// 诊断上下文取 origin 原始字段，不解析 PrettyPrinter 的排版行。
  void _feedErrorReport(OutputEvent event) {
    final reportLevel = switch (event.level) {
      Level.error => ErrorReportLevel.error,
      Level.warning => ErrorReportLevel.warning,
      _ => null,
    };
    if (reportLevel == null) return;
    final origin = event.origin;
    final base = origin.message?.toString() ?? '';
    final error = origin.error;
    errorReportNotifier.add(
      level: reportLevel,
      source: '应用',
      message: error == null ? base : '$base: $error',
      time: origin.time,
    );
  }

  Future<IOSink?> _ensureFileSink() async {
    if (_fileSink != null) return _fileSink;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${dir.path}/logs');
      if (!logDir.existsSync()) logDir.createSync(recursive: true);
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final path = '${logDir.path}/mofox_$today.log';
      _fileSink = File(path).openWrite(mode: FileMode.append);
      // 启动分隔
      _fileSink!.writeln();
      _fileSink!.writeln(
        '=== MoFox log session ${DateTime.now().toIso8601String()} ===',
      );
      return _fileSink;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> destroy() async {
    await _fileSink?.flush();
    await _fileSink?.close();
    _fileSink = null;
    await super.destroy();
  }
}

/// 当前日志文件路径（供设置页"导出日志"用）。
Future<String?> currentLogFilePath() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return '${dir.path}/logs/mofox_$today.log';
  } catch (_) {
    return null;
  }
}

/// 导出 / 分享当前日志文件。
Future<void> shareLogFile(BuildContext context) async {
  final path = await currentLogFilePath();
  if (path == null) return;
  final file = File(path);
  if (!file.existsSync()) return;
  await Share.shareXFiles(
    <XFile>[XFile(path)],
    text: 'MoFox 日志 $path',
  );
}

/// Riverpod provider：暴露 [appLogger] 给 widget 树。
final Provider<Logger> appLoggerProvider = Provider<Logger>(
  (ref) => appLogger,
);
