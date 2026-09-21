import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/wizard/presentation/widgets/napcat_qr_sheet.dart';

void main() {
  test('extracts the file path without the refresh version', () {
    expect(
      napcatQrImagePath('file:/data/user/0/mofox/qrcode.png#123456'),
      '/data/user/0/mofox/qrcode.png',
    );
    expect(
      napcatQrImagePath('file:/data/user/0/mofox/qrcode.png'),
      '/data/user/0/mofox/qrcode.png',
    );
    expect(napcatQrImagePath('https://example.com/qr'), isNull);
  });

  test('reloads bytes when NapCat overwrites the same QR path', () async {
    final directory = await Directory.systemTemp.createTemp('mofox-qr-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/qrcode.png');
    final firstBytes = base64Decode(_transparentPng);
    final secondBytes = base64Decode(_blackPng);
    await file.writeAsBytes(firstBytes);

    expect(napcatQrImageBytes('file:${file.path}#1'), firstBytes);

    await file.writeAsBytes(secondBytes, flush: true);
    expect(napcatQrImageBytes('file:${file.path}#2'), secondBytes);
  });

  testWidgets('offers a labelled and guarded non-visual login alternative', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const loginInfo = 'https://example.com/login?ticket=sensitive';
    String? copiedText;
    final keepScreenOnValues = <bool>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('mofox/platform'),
      (call) async {
        if (call.method == 'setKeepScreenOn') {
          final arguments = call.arguments! as Map<Object?, Object?>;
          keepScreenOnValues.add(arguments['enabled']! as bool);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('mofox/platform'),
        null,
      ),
    );
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: const TextScaler.linear(1.4),
            ),
            child: child!,
          ),
          home: const Scaffold(
            body: NapcatQrSheet(payload: loginInfo),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('QQ 登录二维码'), findsOneWidget);
    expect(find.text(loginInfo), findsNothing);
    final copyButton = find.widgetWithText(FilledButton, '复制登录信息');
    await tester.ensureVisible(copyButton);
    expect(tester.getSize(copyButton).height, greaterThanOrEqualTo(48));
    await tester.tap(copyButton);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '复制'));
    await tester.pumpAndSettle();

    expect(copiedText, loginInfo);
    expect(find.text('登录信息已复制；使用后请清空剪贴板'), findsOneWidget);
    expect(keepScreenOnValues, <bool>[true]);
    expect(tester.takeException(), isNull);
    semantics.dispose();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(keepScreenOnValues, <bool>[true, false]);
  });

  test('local QR paths are never exposed as copyable login data', () {
    expect(
      napcatQrCopyableLoginInfo('file:/data/user/0/mofox/qr.png#2'),
      isNull,
    );
    expect(napcatQrCopyableLoginInfo('  login-value  '), 'login-value');
  });
}

// 两张有效的 1×1 PNG，用于验证同路径覆盖后的字节刷新。
const String _transparentPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
const String _blackPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=';
