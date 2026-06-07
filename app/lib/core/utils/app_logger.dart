import 'package:logger/logger.dart';

/// 全局日志器；只面向原生壳本身，Bot 业务日志在 WebUI 看。
final Logger appLogger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    lineLength: 100,
    colors: true,
    printEmojis: false,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
);
