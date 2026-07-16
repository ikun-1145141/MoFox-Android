import 'dart:convert';
import 'dart:io';

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
}

// 两张有效的 1×1 PNG，用于验证同路径覆盖后的字节刷新。
const String _transparentPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
const String _blackPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=';
