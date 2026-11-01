import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mofox_android/core/theme/app_theme.dart';
import 'package:mofox_android/core/ui/app_components.dart';
import 'package:mofox_android/features/settings/application/app_settings_provider.dart';

/// 设备能力服务设置：把本机通知/短信作为受控数据源暴露给 bot 实例。
///
/// 授权状态与采集器运行状态由原生服务接入后在此补充；当前先落
/// 总开关与各数据源开关，开关状态持久化并驱动 device-service.json。
class DeviceCapabilityPage extends ConsumerWidget {
  const DeviceCapabilityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设备能力服务')),
      body: settings.when(
        loading: () => const AppLoadingState(label: '正在加载设置'),
        error: (_, __) => AppErrorState(
          title: '设置加载失败',
          message: '暂时无法读取本机设置，请重试。',
          onRetry: () => ref.invalidate(appSettingsProvider),
        ),
        data: (appSettings) {
          final master = appSettings.deviceCapabilityEnabled;
          return AppPageList(
            children: <Widget>[
              AppSectionCard(
                title: '服务',
                children: <Widget>[
                  AppSwitchSettingTile(
                    title: '启用设备能力服务',
                    subtitle: '开启后 bot 实例可通过本机接口读取下述数据源',
                    value: master,
                    onChanged: (value) => ref
                        .read(appSettingsProvider.notifier)
                        .setDeviceCapabilityEnabled(value),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppSectionCard(
                title: '数据源',
                children: <Widget>[
                  AppSwitchSettingTile(
                    title: '通知源',
                    subtitle: '捕获应用通知，供 bot 读取',
                    value: appSettings.deviceCapabilityNotificationsEnabled,
                    onChanged: master
                        ? (value) => ref
                            .read(appSettingsProvider.notifier)
                            .setDeviceCapabilityNotificationsEnabled(value)
                        : null,
                  ),
                  AppSwitchSettingTile(
                    title: '短信源',
                    subtitle: '读取新短信，供 bot 读取；开启时需授予短信权限',
                    value: appSettings.deviceCapabilitySmsEnabled,
                    onChanged: master
                        ? (value) => ref
                            .read(appSettingsProvider.notifier)
                            .setDeviceCapabilitySmsEnabled(value)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const AppSectionCard(
                title: '隐私',
                children: <Widget>[
                  AppSettingTile(
                    leading: Icon(Icons.privacy_tip_outlined),
                    title: '数据边界',
                    subtitle:
                        '数据仅在本机 127.0.0.1 与 bot 实例之间流转，不上传网络；接口需要本机令牌，其他应用无法读取',
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
