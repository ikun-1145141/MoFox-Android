import 'package:flutter/material.dart';

class TerminalPage extends StatelessWidget {
  const TerminalPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('终端'),
        actions: <Widget>[
          IconButton(
            tooltip: '清屏',
            onPressed: () {},
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
          IconButton(
            tooltip: '复制全部',
            onPressed: () {},
            icon: const Icon(Icons.content_copy_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          children: <Widget>[
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Text(
                    r'$ # 终端占位'
                    '\n'
                    r'$ # 接通 RuntimeBridge.openPty 之后挂上 xterm.dart 渲染'
                    '\n'
                    r'$ _',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    enabled: false,
                    decoration: InputDecoration(
                      hintText: '在此输入命令…',
                      filled: true,
                      fillColor: scheme.surfaceContainer,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: null,
                  icon: const Icon(Icons.send),
                  label: const Text('执行'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
