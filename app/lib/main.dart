import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/mofox_app.dart';
import 'core/utils/app_logger.dart';

Future<void> main() async {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (FlutterErrorDetails details) {
        appLogger.e(
          'Flutter framework error',
          error: details.exception,
          stackTrace: details.stack,
        );
      };
      appLogger.i('MoFox 启动中…');
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      appLogger.d('屏幕方向已设置');
      runApp(const ProviderScope(child: MoFoxApp()));
    },
    (Object error, StackTrace stack) {
      appLogger.e('未捕获的异步异常', error: error, stackTrace: stack);
    },
  );
}
