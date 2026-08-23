import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html_parser;

class MofoxDocsMcpClient {
  MofoxDocsMcpClient([Dio? dio]) : _dio = dio ?? Dio();

  static const String _algoliaUrl =
      'https://JZV5IVO9JD-dsn.algolia.net/1/indexes/Mofox-Docs/query';
  static const String _appId = 'JZV5IVO9JD';
  static const String _searchKey = 'e39ee94d8116ce8958647991de0f9637';
  static const Duration _cacheDuration = Duration(minutes: 5);

  final Dio _dio;
  final Map<String, _CachedText> _cache = <String, _CachedText>{};
  int _requestId = 0;
  bool _initialized = false;

  Future<List<Map<String, Object?>>> listTools() async {
    await _initialize();
    final response = await _request('tools/list');
    final tools = (response['tools'] as List<Object?>?) ?? const <Object?>[];
    return tools.cast<Map<String, Object?>>();
  }

  Future<String> callTool(
    String name,
    Map<String, Object?> arguments,
  ) async {
    await _initialize();
    final response = await _request(
      'tools/call',
      <String, Object?>{'name': name, 'arguments': arguments},
    );
    final content =
        (response['content'] as List<Object?>?) ?? const <Object?>[];
    return content
        .whereType<Map<String, Object?>>()
        .where((item) => item['type'] == 'text')
        .map((item) => item['text']?.toString() ?? '')
        .where((text) => text.isNotEmpty)
        .join('\n');
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    await _request(
      'initialize',
      <String, Object?>{
        'protocolVersion': '2025-06-18',
        'capabilities': <String, Object?>{},
        'clientInfo': <String, Object?>{
          'name': 'MoFox-Android',
          'version': '1.0.0',
        },
      },
    );
    _initialized = true;
  }

  Future<Map<String, Object?>> _request(
    String method, [
    Map<String, Object?>? params,
  ]) async {
    final request = <String, Object?>{
      'jsonrpc': '2.0',
      'id': ++_requestId,
      'method': method,
      if (params != null) 'params': params,
    };
    final response = await _handleRequest(request);
    final error = response['error'];
    if (error != null) throw StateError('文档 MCP 错误：$error');
    return (response['result'] as Map<String, Object?>?) ??
        const <String, Object?>{};
  }

  Future<Map<String, Object?>> _handleRequest(
    Map<String, Object?> request,
  ) async {
    final id = request['id'];
    try {
      final result = switch (request['method']) {
        'initialize' => <String, Object?>{
            'protocolVersion': '2025-06-18',
            'capabilities': <String, Object?>{
              'tools': <String, Object?>{'listChanged': false},
            },
            'serverInfo': <String, Object?>{
              'name': 'mofox-live-docs',
              'version': '1.0.0',
            },
          },
        'tools/list' => <String, Object?>{'tools': _tools},
        'tools/call' => await _callTool(
            (request['params'] as Map<String, Object?>?) ??
                const <String, Object?>{},
          ),
        _ => throw UnsupportedError('不支持的 MCP 方法：${request['method']}'),
      };
      return <String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result};
    } on Object catch (error) {
      return <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{'code': -32603, 'message': '$error'},
      };
    }
  }

  Future<Map<String, Object?>> _callTool(Map<String, Object?> params) async {
    final name = params['name']?.toString() ?? '';
    final arguments = (params['arguments'] as Map<String, Object?>?) ??
        const <String, Object?>{};
    final text = switch (name) {
      'search_mofox_docs' => await _search(
          arguments['query']?.toString() ?? '',
          _boundedInt(arguments['limit'], fallback: 5, min: 1, max: 8),
        ),
      'read_mofox_doc' => await _read(
          arguments['url']?.toString() ?? '',
          _boundedInt(
            arguments['max_chars'],
            fallback: 8000,
            min: 500,
            max: 16000,
          ),
        ),
      _ => throw ArgumentError.value(name, 'name', '未知文档 MCP 工具'),
    };
    return <String, Object?>{
      'content': <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'text': text},
      ],
    };
  }

  Future<String> _search(String query, int limit) async {
    final normalized = query.trim();
    if (normalized.isEmpty) throw const FormatException('文档检索词不能为空');
    return _cached('search:$normalized:$limit', () async {
      final response = await _withRetry(
        () => _dio.post<Map<String, Object?>>(
          _algoliaUrl,
          data: <String, Object?>{
            'query': normalized,
            'hitsPerPage': (limit * 4).clamp(8, 32),
            'attributesToRetrieve': <String>[
              'hierarchy',
              'content',
              'url',
              'anchor',
            ],
          },
          options: Options(
            headers: const <String, String>{
              'x-algolia-application-id': _appId,
              'x-algolia-api-key': _searchKey,
            },
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
          ),
        ),
      );
      final hits =
          response.data?['hits'] as List<Object?>? ?? const <Object?>[];
      final results = <String>[];
      final seenPages = <String>{};
      for (final raw in hits.whereType<Map<String, Object?>>()) {
        final hierarchy = raw['hierarchy'] as Map<String, Object?>? ??
            const <String, Object?>{};
        var title = raw['anchor']?.toString() ?? 'Neo-MoFox 文档';
        for (var level = 6; level >= 1; level--) {
          final value = hierarchy['lvl$level']?.toString().trim();
          if (value != null && value.isNotEmpty) {
            title = value;
            break;
          }
        }
        final url = raw['url']?.toString() ?? 'https://docs.mofox-sama.com';
        final pageKey = _canonicalPageKey(url);
        if (!seenPages.add(pageKey)) continue;
        final content = raw['content']?.toString().trim() ?? '';
        results.add('[$title]\nsource: $url\n${_take(content, 700)}');
        if (results.length >= limit) break;
      }
      return results.isEmpty ? '未找到相关官方文档。' : results.join('\n\n');
    });
  }

  Future<String> _read(String value, int maximum) async {
    final cleaned = RegExp(r'https://docs\.mofox-sama\.com/[^\s<>"\]]*')
            .firstMatch(value.trim())
            ?.group(0)
            ?.replaceFirst(RegExp(r'[),，。；;]+$'), '') ??
        value.trim();
    final uri = Uri.tryParse(cleaned);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'docs.mofox-sama.com') {
      throw const FormatException('只允许读取 docs.mofox-sama.com 的 HTTPS 页面');
    }
    return _cached('read:${uri.replace(fragment: '')}:$maximum', () async {
      final response = await _withRetry(
        () => _dio.get<String>(
          uri.replace(fragment: '').toString(),
          options: Options(
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 20),
          ),
        ),
      );
      final document = html_parser.parse(response.data ?? '');
      final article = document.querySelector('.vp-doc');
      if (article == null) throw const FormatException('官方文档页面缺少正文');
      for (final element
          in article.querySelectorAll('script,style,svg,button')) {
        element.remove();
      }
      final text = article.text
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .replaceAll(RegExp(r'\n\s*\n+'), '\n\n')
          .trim();
      return '来源：$uri\n\n${_take(text, maximum)}';
    });
  }

  Future<String> _cached(String key, Future<String> Function() loader) async {
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) < _cacheDuration) {
      return cached.text;
    }
    final text = await loader();
    _cache[key] = _CachedText(text, DateTime.now());
    return text;
  }

  Future<Response<T>> _withRetry<T>(
    Future<Response<T>> Function() operation,
  ) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await operation();
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        final transient = status == 429 ||
            (status != null && status >= 500) ||
            error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.sendTimeout;
        if (!transient || attempt >= 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
  }

  String _canonicalPageKey(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return value;
    var path = uri.path.replaceFirst(RegExp(r'\.html$'), '');
    if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    return path.toLowerCase();
  }

  int _boundedInt(
    Object? value, {
    required int fallback,
    required int min,
    required int max,
  }) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return (parsed ?? fallback).clamp(min, max);
  }

  String _take(String value, int maximum) =>
      value.length <= maximum ? value : '${value.substring(0, maximum)}\n（已截断）';
}

const List<Map<String, Object?>> _tools = <Map<String, Object?>>[
  <String, Object?>{
    'name': 'search_mofox_docs',
    'description': '实时检索 Neo-MoFox 官方文档网站，返回当前页面摘要和来源链接。',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'query': <String, Object?>{'type': 'string'},
        'limit': <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 8,
        },
      },
      'required': <String>['query'],
    },
  },
  <String, Object?>{
    'name': 'read_mofox_doc',
    'description': '实时读取 docs.mofox-sama.com 的官方文档页面正文。',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'url': <String, Object?>{'type': 'string'},
        'max_chars': <String, Object?>{
          'type': 'integer',
          'minimum': 500,
          'maximum': 16000,
        },
      },
      'required': <String>['url'],
    },
  },
];

class _CachedText {
  const _CachedText(this.text, this.createdAt);

  final String text;
  final DateTime createdAt;
}

final mofoxDocsMcpProvider = Provider<MofoxDocsMcpClient>(
  (_) => MofoxDocsMcpClient(),
);
