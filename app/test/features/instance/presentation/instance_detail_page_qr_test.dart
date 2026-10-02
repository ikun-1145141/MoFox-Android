import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/dashboard/application/process_console_provider.dart';
import 'package:mofox_android/features/instance/domain/instance.dart';
import 'package:mofox_android/features/instance/presentation/instance_detail_page.dart';
import 'package:mofox_android/features/wizard/presentation/widgets/snowluma_qr_sheet.dart';

/// 固定状态的 ProcessConsoleNotifier：测试里直接改 `state` 模拟事件流。
class _FakeConsoleNotifier extends ProcessConsoleNotifier {
  @override
  ProcessConsoleState build() => ProcessConsoleState.initial();
}

Instance _instance() => Instance(
      id: 'inst-test',
      name: '测试实例',
      botQq: '10000',
      botNickname: 'bot',
      ownerQq: '10001',
      wsPort: 8095,
      channel: 'main',
      installSnowluma: true,
      installWebui: false,
      installDir: '/root/instances/inst-test',
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  late Directory tempDir;
  late File qrFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mofox-detail-qr-');
    qrFile = File('${tempDir.path}/screen.png');
    await qrFile.writeAsBytes(_transparentPng);
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } on FileSystemException {
      // Windows 下页面仍持有文件句柄时忽略，留给系统清理临时目录。
    }
  });

  bool qrPanelVisible(WidgetTester tester) =>
      find.byType(SnowlumaQrSheet).evaluate().isNotEmpty;

  testWidgets('QR panel shows while running, live-refreshes, hides on stop',
      (tester) async {
    // 面板最高占屏幕 85%，小视口里按钮会被滚出可视区；用足够高的视口测试。
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('mofox/runtime'),
      (call) async => null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('mofox/platform'),
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('mofox/runtime'),
        null,
      ),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('mofox/platform'),
        null,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          processConsoleProvider.overrideWith(_FakeConsoleNotifier.new),
        ],
        child: MaterialApp(home: InstanceDetailPage(instance: _instance())),
      ),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(InstanceDetailPage)),
    );
    final notifier = container.read(processConsoleProvider.notifier);

    ProcessConsoleState stateWith({
      String snowlumaStatus = 'running',
      String? payload,
    }) =>
        ProcessConsoleState.initial().copyWith(
          status: <String, String>{
            'bot': 'running',
            'snowluma': snowlumaStatus,
          },
          activeInstanceId: 'inst-test',
          snowlumaQrPayload: payload,
        );

    // 首个截图 payload（桌面）→ 浮层显示
    notifier.state = stateWith(payload: 'file:${qrFile.path}#1');
    await tester.pump();
    expect(qrPanelVisible(tester), isTrue, reason: '运行中且 payload 非空应显示浮层');

    // 二维码刷新（新文件+新版本号）→ 浮层原地更新，不消失
    final qrFile2 = File('${tempDir.path}/screen2.png');
    await tester.runAsync(() => qrFile2.writeAsBytes(_blackPng, flush: true));
    notifier.state = stateWith(payload: 'file:${qrFile2.path}#2');
    await tester.pump();
    expect(qrPanelVisible(tester), isTrue, reason: 'payload 刷新不应隐藏浮层');
    final images = find
        .byWidgetPredicate((w) => w.runtimeType.toString() == '_QrFileImage')
        .evaluate();
    expect(images, isNotEmpty);
    final image = images.single.widget as dynamic;
    expect(image.cacheKey, 'file:${qrFile2.path}#2', reason: '应展示最新截图');

    // 登录成功：payload 清空 → 浮层隐藏
    notifier.state = stateWith();
    await tester.pump();
    expect(qrPanelVisible(tester), isFalse, reason: 'payload 清空后应隐藏浮层');

    // 取消登录：点击取消按钮 → 浮层隐藏且 snowluma 被停止
    notifier.state = stateWith(payload: 'file:${qrFile.path}#3');
    await tester.pump();
    expect(qrPanelVisible(tester), isTrue, reason: '新一轮登录应重新显示浮层');

    // 点遮罩手动收起：浮层隐藏但 snowluma 仍在运行，出现恢复按钮
    await tester.tapAt(const Offset(200, 15));
    await tester.pump();
    expect(qrPanelVisible(tester), isFalse, reason: '点遮罩应收起浮层');
    expect(find.text('查看扫码窗口'), findsOneWidget);
    expect(
      notifier.state.snowlumaStatusFor('inst-test'),
      'running',
      reason: '收起浮层不应停止进程',
    );

    // 点恢复按钮 → 浮层重新显示
    await tester.tap(find.text('查看扫码窗口'));
    await tester.pump();
    expect(qrPanelVisible(tester), isTrue, reason: '恢复按钮应重新显示浮层');

    // 取消登录 → 浮层隐藏且 snowluma 被停止
    await tester.tap(find.text('取消登录'));
    await tester.pump();
    expect(qrPanelVisible(tester), isFalse, reason: '取消登录后应隐藏浮层');
    expect(
      notifier.state.snowlumaStatusFor('inst-test'),
      'stopped',
      reason: '取消登录应停止 snowluma 进程',
    );

    // 重新启动并出新码 → 浮层可再次显示
    notifier.state = stateWith(payload: 'file:${qrFile.path}#4');
    await tester.pump();
    expect(qrPanelVisible(tester), isTrue, reason: '重启后应再次显示浮层');

    // 进程停止 → 浮层隐藏
    notifier.state = stateWith(snowlumaStatus: 'stopped');
    await tester.pump();
    expect(qrPanelVisible(tester), isFalse, reason: '进程停止后应隐藏浮层');
  });
}

const _transparentPng = <int>[
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
];

const _blackPng = <int>[
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
];
