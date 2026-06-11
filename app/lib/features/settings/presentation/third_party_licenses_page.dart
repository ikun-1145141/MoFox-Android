import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>(
  (_) => PackageInfo.fromPlatform(),
);

class ThirdPartyLicensesPage extends ConsumerWidget {
  const ThirdPartyLicensesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packageInfo = ref.watch(_packageInfoProvider);
    final version = packageInfo.maybeWhen(
      data: (info) => '${info.version} (${info.buildNumber})',
      orElse: () => null,
    );

    return LicensePage(
      applicationName: 'MoFox Android',
      applicationVersion: version,
      applicationLegalese: 'Released under AGPL-3.0',
      applicationIcon: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Icon(
          Icons.android,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
