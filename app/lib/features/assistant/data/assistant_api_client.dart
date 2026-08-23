import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/assistant_settings_notifier.dart';
import '../domain/assistant_models.dart';

class AssistantApiClient {
  AssistantApiClient([Dio? dio]) : _dio = dio ?? Dio();

  final Dio _dio;

  Stream<String> streamChat({
    required AssistantSettings settings,
    required String apiKey,
    required String systemPrompt,
    required List<AssistantMessage> messages,
    CancelToken? cancelToken,
  }) async* {
    final response = await _dio.post<ResponseBody>(
      _chatUri(settings).toString(),
      data: <String, Object>{
        'model': settings.model,
        'stream': true,
        'messages': <Map<String, String>>[
          <String, String>{'role': 'system', 'content': systemPrompt},
          ...messages.map((message) => message.toApiJson()),
        ],
      },
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: false,
        headers: <String, String>{
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream, application/json',
        },
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 2),
      ),
      cancelToken: cancelToken,
    );
    final body = response.data;
    if (body == null) throw const FormatException('模型服务返回空响应');

    var sawSse = false;
    final nonStream = StringBuffer();
    final lines = body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) {
        if (!sawSse && line.trim().isNotEmpty) nonStream.writeln(line);
        continue;
      }
      sawSse = true;
      final data = line.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      final content = _contentFromJson(jsonDecode(data));
      if (content.isNotEmpty) yield content;
    }

    if (!sawSse && nonStream.isNotEmpty) {
      final content = _contentFromJson(jsonDecode(nonStream.toString()));
      if (content.isNotEmpty) yield content;
    }
  }

  Future<void> testConnection({
    required AssistantSettings settings,
    required String apiKey,
  }) async {
    await streamChat(
      settings: settings,
      apiKey: apiKey,
      systemPrompt: '只回复 OK。',
      messages: const <AssistantMessage>[
        AssistantMessage(role: AssistantRole.user, text: '连接测试'),
      ],
    ).first.timeout(const Duration(seconds: 30));
  }

  Uri _chatUri(AssistantSettings settings) {
    final value = settings.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      value.endsWith('/chat/completions') ? value : '$value/chat/completions',
    );
    final local =
        uri.host == '127.0.0.1' || uri.host == 'localhost' || uri.host == '::1';
    if (!uri.hasScheme ||
        (uri.scheme != 'https' && !local && !settings.allowInsecureHttp)) {
      throw const FormatException(
        '外部 HTTP 会明文传输 API Key，请先在设置中明确允许不安全 HTTP',
      );
    }
    return uri;
  }

  String _contentFromJson(Object? decoded) {
    if (decoded is! Map<String, Object?>) return '';
    final choices = decoded['choices'];
    if (choices is! List<Object?> || choices.isEmpty) return '';
    final first = choices.first;
    if (first is! Map<String, Object?>) return '';
    final delta = first['delta'];
    if (delta is Map<String, Object?>) {
      return delta['content']?.toString() ?? '';
    }
    final message = first['message'];
    if (message is Map<String, Object?>) {
      return message['content']?.toString() ?? '';
    }
    return first['text']?.toString() ?? '';
  }
}

final assistantApiClientProvider = Provider<AssistantApiClient>(
  (_) => AssistantApiClient(),
);
