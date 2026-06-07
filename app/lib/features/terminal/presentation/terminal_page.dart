import 'package:flutter/material.dart';

class TerminalPage extends StatelessWidget {
  const TerminalPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('终端')),
      body: Container(
        color: scheme.surfaceContainerHighest,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '终端占位\n\n接通 RuntimeBridge.openPty 之后，挂上 xterm.dart 渲染。',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
