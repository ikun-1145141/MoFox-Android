/// 日志脱敏：进程控制台与「报错汇总」共用。
///
/// 截图/复制给 AI 前必须过这里：URL 查询参数、键值对、Bearer 头里的 token /
/// api_key / password / secret 一律替换为 `[REDACTED]`。
String redactSensitiveLogLine(String line) {
  final querySecret = RegExp(
    r'([?&](?:token|access_token|api[_-]?key|secret)=)[^&\s]+',
    caseSensitive: false,
  );
  final assignedSecret = RegExp(
    r'(\b(?:token|access[_-]?token|api[_-]?key|password|secret)\s*[:=]\s*)\S+',
    caseSensitive: false,
  );
  final bearerSecret = RegExp(r'(\bBearer\s+)\S+', caseSensitive: false);
  return line
      .replaceAllMapped(querySecret, (match) => '${match.group(1)}[REDACTED]')
      .replaceAllMapped(
        assignedSecret,
        (match) => '${match.group(1)}[REDACTED]',
      )
      .replaceAllMapped(bearerSecret, (match) => '${match.group(1)}[REDACTED]');
}
