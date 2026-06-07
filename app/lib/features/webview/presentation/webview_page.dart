import 'package:flutter/material.dart';

enum WebUiTarget { neoMofox, napcat }

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});
  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  WebUiTarget _target = WebUiTarget.neoMofox;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SegmentedButton<WebUiTarget>(
              segments: const <ButtonSegment<WebUiTarget>>[
                ButtonSegment(
                  value: WebUiTarget.neoMofox,
                  label: Text('Neo-MoFox'),
                  icon: Icon(Icons.dashboard_outlined),
                ),
                ButtonSegment(
                  value: WebUiTarget.napcat,
                  label: Text('Napcat'),
                  icon: Icon(Icons.qr_code_2_outlined),
                ),
              ],
              selected: <WebUiTarget>{_target},
              onSelectionChanged: (s) => setState(() => _target = s.first),
            ),
          ),
        ),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'WebView 占位。后续这里通过 webview_flutter 加载 '
            'http://127.0.0.1:8000/webui/ 与 Napcat 控制台。',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
