class SystemStats {
  const SystemStats({
    required this.socName,
    required this.memoryTotal,
    required this.memoryAvailable,
    required this.memoryUsed,
    required this.storageTotal,
    required this.storageAvailable,
    required this.storageUsed,
    required this.appDataTotal,
    required this.appDataAvailable,
    required this.deviceName,
    required this.androidVersion,
    required this.sdkInt,
    required this.supportedAbis,
    required this.kernel,
    required this.rootfsPath,
    required this.appDataPath,
  });

  final String socName;
  final int memoryTotal;
  final int memoryAvailable;
  final int memoryUsed;
  final int storageTotal;
  final int storageAvailable;
  final int storageUsed;
  final int appDataTotal;
  final int appDataAvailable;
  final String deviceName;
  final String androidVersion;
  final int sdkInt;
  final String supportedAbis;
  final String kernel;
  final String rootfsPath;
  final String appDataPath;

  double get memoryUsage => _ratio(memoryUsed, memoryTotal);
  double get storageUsage => _ratio(storageUsed, storageTotal);

  factory SystemStats.fromMap(Map<Object?, Object?> map) {
    return SystemStats(
      socName: map['socName']?.toString() ?? '',
      memoryTotal: _int(map['memoryTotal']),
      memoryAvailable: _int(map['memoryAvailable']),
      memoryUsed: _int(map['memoryUsed']),
      storageTotal: _int(map['storageTotal']),
      storageAvailable: _int(map['storageAvailable']),
      storageUsed: _int(map['storageUsed']),
      appDataTotal: _int(map['appDataTotal']),
      appDataAvailable: _int(map['appDataAvailable']),
      deviceName: map['deviceName']?.toString() ?? 'Unknown device',
      androidVersion: map['androidVersion']?.toString() ?? 'Unknown',
      sdkInt: _int(map['sdkInt']),
      supportedAbis: map['supportedAbis']?.toString() ?? 'Unknown',
      kernel: map['kernel']?.toString() ?? 'Unknown',
      rootfsPath: map['rootfsPath']?.toString() ?? '',
      appDataPath: map['appDataPath']?.toString() ?? '',
    );
  }

  static double _ratio(int used, int total) {
    if (total <= 0) return 0;
    return (used / total).clamp(0, 1).toDouble();
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
