import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import 'router/app_router.dart';

class MoFoxApp extends ConsumerWidget {
  const MoFoxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return DynamicTheme(
      builder: (context, lightScheme, darkScheme) {
        return MaterialApp.router(
          title: 'MoFox',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(lightScheme),
          darkTheme: AppTheme.dark(darkScheme),
          themeMode: ThemeMode.system,
          routerConfig: router,
          builder: (context, child) {
            // edge-to-edge：让壁纸 / 状态栏背景透到内容下面，
            // 系统栏图标颜色由 ThemeData 自动决定。
            final brightness = Theme.of(context).brightness;
            SystemChrome.setSystemUIOverlayStyle(
              SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarDividerColor: Colors.transparent,
                statusBarIconBrightness:
                    brightness == Brightness.light ? Brightness.dark : Brightness.light,
                systemNavigationBarIconBrightness:
                    brightness == Brightness.light ? Brightness.dark : Brightness.light,
              ),
            );
            return child ?? const SizedBox.shrink();
          },
        );
      },
    );
  }
}
