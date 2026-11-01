import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mofox_android/core/utils/log_redaction.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 报错汇总条目的级别。
enum ErrorReportLevel {
  /// 明确的报错（进程退出、安装失败、异常堆栈等）。
  error,

  /// 警告（可恢复的失败、降级）。
  warning,

  /// 关键诊断行（SnowLuma 的 `[control]` 行：自检、get_status 解读、hook 诊断）。
  /// AI 靠这些行定性问题，级别虽低但诊断价值最高。
  diag,
}

/// 「报错汇总」的单条记录。相邻同源同文的行折叠为一条，`repeat` 计重复次数。
class ErrorReportEntry {
  const ErrorReportEntry({
    required this.time,
    required this.level,
    required this.source,
    required this.message,
    this.repeat = 1,
  });

  final DateTime time;
  final ErrorReportLevel level;

  /// 来源标签：应用 / SnowLuma / Bot / 安装。
  final String source;
  final String message;
  final int repeat;
}

/// 本次启动的报错/诊断环形缓冲。
///
/// 喂食点：
/// - `_MoFoxLogOutput.output`（appLogger 的 error/warning 全部流经此处）；
/// - `processConsoleProvider` 的 bot/SnowLuma 日志追加处（按 [addProcessLine]
///   的规则过滤）。
///
/// 纯内存、不持久化——「本次启动」语义即从 App 冷启动开始累计；完整历史
/// 走按天滚动的文件日志（见 app_logger.dart）。
class ErrorReportNotifier extends StateNotifier<List<ErrorReportEntry>> {
  ErrorReportNotifier() : super(const <ErrorReportEntry>[]);

  /// 缓冲上限：满后丢最旧。报错 + `[control]` 诊断行一个会话通常几十条，
  /// 300 足够覆盖极端会话且保证截图信息密度。
  static const int maxEntries = 300;

  /// 单条消息截断长度，防异常堆栈把截图撑爆（完整堆栈在文件日志里）。
  static const int _maxMessageLength = 600;

  /// 进程日志中的错误行模式。'失败' 覆盖中文自愈/控制行，
  /// 'exited with' 是原生进程退出标记，Traceback/Exception 覆盖 bot 侧 Python。
  static final RegExp processErrorLinePattern = RegExp(
    '✗|失败|exited with|Traceback|Exception|ERROR',
  );

  /// 追加一条记录：脱敏 → 截断 → 折叠 → 封顶。
  void add({
    required ErrorReportLevel level,
    required String source,
    required String message,
    DateTime? time,
  }) {
    final clean = redactSensitiveLogLine(message).trim();
    if (clean.isEmpty) return;
    final trimmed = clean.length > _maxMessageLength
        ? '${clean.substring(0, _maxMessageLength)}…'
        : clean;
    final entries = state;
    if (entries.isNotEmpty) {
      final last = entries.last;
      if (last.source == source && last.message == trimmed) {
        // 折叠：时间取最近一次出现，重复次数 +1。
        final merged = ErrorReportEntry(
          time: time ?? DateTime.now(),
          level: last.level,
          source: last.source,
          message: last.message,
          repeat: last.repeat + 1,
        );
        state = <ErrorReportEntry>[
          ...entries.sublist(0, entries.length - 1),
          merged,
        ];
        return;
      }
    }
    final next = <ErrorReportEntry>[
      ...entries,
      ErrorReportEntry(
        time: time ?? DateTime.now(),
        level: level,
        source: source,
        message: trimmed,
      ),
    ];
    state = next.length > maxEntries
        ? next.sublist(next.length - maxEntries)
        : next;
  }

  /// 进程日志喂食规则：
  /// - 任何来源的错误模式行 → error；
  /// - SnowLuma 的 `[control]` 诊断行 → diag（自检/get_status 解读等）；
  /// - Bot 的其余行不收——正常日志量大且诊断价值低，全收会把截图撑爆。
  void addProcessLine({
    required String source,
    required String line,
    DateTime? time,
  }) {
    if (processErrorLinePattern.hasMatch(line)) {
      add(level: ErrorReportLevel.error, source: source, message: line, time: time);
      return;
    }
    if (source == 'SnowLuma' && line.startsWith('[control]')) {
      add(level: ErrorReportLevel.diag, source: source, message: line, time: time);
    }
  }

  void clear() => state = const <ErrorReportEntry>[];

  /// 「复制全部」文本：设备头 + 按时间序的全部条目。
  ///
  /// 设备头（机型/系统/App 版本）对 AI 排查很关键且无隐私顾虑；正文已在
  /// [add] 入口统一脱敏。
  Future<String> buildExportText() async {
    final head = StringBuffer('MoFox');
    try {
      final info = await PackageInfo.fromPlatform();
      head.write(' ${info.version} (${info.buildNumber})');
    } on Object {
      // 版本信息拿不到不影响正文。
    }
    try {
      final android = await DeviceInfoPlugin().androidInfo;
      head.write(
        ' | ${android.model} | Android ${android.version.release}'
        ' (SDK ${android.version.sdkInt})',
      );
    } on Object {
      // 非 Android 环境（测试）跳过机型信息。
    }
    head.write(' | 导出时间 ${DateTime.now().toIso8601String()}');

    final buffer = StringBuffer(head.toString());
    for (final entry in state) {
      buffer.writeln();
      final repeat = entry.repeat > 1 ? ' ×${entry.repeat}' : '';
      buffer.write(
        '${formatTime(entry.time)} [${entry.source}$repeat] ${entry.message}',
      );
    }
    return buffer.toString();
  }

  /// HH:mm:ss，页面与导出文本共用。
  static String formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}

/// 全局单例：appLogger 输出等拿不到 ref 的环境直接调 [errorReportNotifier]。
/// Provider 暴露同一实例给 widget 树。
final ErrorReportNotifier errorReportNotifier = ErrorReportNotifier();

final StateNotifierProvider<ErrorReportNotifier, List<ErrorReportEntry>>
    errorReportProvider = StateNotifierProvider<ErrorReportNotifier,
        List<ErrorReportEntry>>((ref) => errorReportNotifier);
