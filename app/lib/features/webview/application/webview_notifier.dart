import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/security/webui_key_store.dart';
import '../../../core/utils/app_logger.dart';
import '../../instance/domain/instance.dart';

/// WebView 控制器 + localStorage 注入逻辑。
///
/// 使用方式：
/// 1. `ref.watch(webviewNotifierProvider)` 拿到 [WebViewController]，
///    传给 [WebViewWidget]。
/// 2. 调 [loadNeoMofox] 加载 Neo-MoFox WebUI（注入 api_key 到 localStorage）。
/// 3. 调 [loadNapcat] 加载 NapCat WebUI（URL 自带 token，无需额外注入）。
/// 4. 调 [reload] 刷新当前页。
class WebviewNotifier extends Notifier<WebViewController> {
  @override
  WebViewController build() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);

    unawaited(controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (NavigationRequest req) {
          // 只允许 127.0.0.1 / localhost 的明文 HTTP，外部链接交给系统浏览器
          final uri = Uri.tryParse(req.url);
          final host = uri?.host ?? '';
          if (host == '127.0.0.1' ||
              host == 'localhost' ||
              req.url.startsWith('about:')) {
            return NavigationDecision.navigate;
          }
          // 外部链接交给系统浏览器打开，WebView 内阻止
          unawaited(launchUrl(Uri.parse(req.url)));
          return NavigationDecision.prevent;
        },
      ),
    ));

    return controller;
  }

  /// 加载 Neo-MoFox WebUI。
  ///
  /// 先注入 `localStorage["mofox_token"] = apiKey`，再加载首页
  /// `http://127.0.0.1:8000/webui/frontend`，实现免登录。
  Future<void> loadNeoMofox(Instance instance) async {
    if (!instance.installWebui) {
      appLogger.w('webview: instance ${instance.id} has no webui installed');
      return;
    }
    final apiKey = await WebuiKeyStore.get(instance.id);
    if (apiKey == null || apiKey.isEmpty) {
      appLogger.w('webview: no api_key for instance ${instance.id}');
      // 没有密钥也加载，前端会显示登录页让用户手动输入
    }

    final controller = state;
    // 1. 先加载空白页确保有 document 上下文
    await controller.loadHtmlString(
      '<html><body></body></html>',
      baseUrl: 'http://127.0.0.1:8000/',
    );
    // 2. 注入 localStorage（清旧再写新，避免残留）
    if (apiKey != null && apiKey.isNotEmpty) {
      await controller.runJavaScript(
        'localStorage.clear();'
        'localStorage.setItem("mofox_token", "${_escapeJs(apiKey)}")',
      );
      appLogger.i('webview: injected mofox_token for instance ${instance.id}');
    }
    // 3. 加载 WebUI 首页
    await controller.loadRequest(
      Uri.parse('http://127.0.0.1:8000/webui/frontend'),
    );
  }

  /// 加载 NapCat WebUI。
  ///
  /// NapCat 的 URL 自带 token（`http://127.0.0.1:6099/webui?token=xxx`），
  /// 直接加载即可，无需额外注入。
  Future<void> loadNapcat(String webuiUrl) async {
    final controller = state;
    // 先清掉 Neo-MoFox 的 localStorage，避免跨实例残留
    await controller.loadHtmlString(
      '<html><body></body></html>',
      baseUrl: 'http://127.0.0.1:6099/',
    );
    await controller.runJavaScript('localStorage.clear();');
    appLogger.i('webview: loading napcat webui: $webuiUrl');
    await controller.loadRequest(Uri.parse(webuiUrl));
  }

  /// 刷新当前页。
  Future<void> reload() => state.reload();

  /// 在系统浏览器打开当前 URL。
  Future<void> openInBrowser(String url) async {
    await launchUrl(Uri.parse(url));
  }

  /// 转义 JavaScript 字符串字面量中的特殊字符。
  static String _escapeJs(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
  }
}

final webviewNotifierProvider =
    NotifierProvider<WebviewNotifier, WebViewController>(
  WebviewNotifier.new,
);
