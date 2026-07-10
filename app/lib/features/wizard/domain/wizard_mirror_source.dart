class WizardMirrorSource {
  const WizardMirrorSource({
    required this.id,
    required this.name,
    required this.repoUrl,
    required this.eulaUrl,
    required this.region,
  });

  final String id;
  final String name;
  final String repoUrl;
  final String eulaUrl;
  final String region;

  String get displayUrl => repoUrl.endsWith('.git')
      ? repoUrl.substring(0, repoUrl.length - 4)
      : repoUrl;
}

const List<WizardMirrorSource> wizardMirrorSources = <WizardMirrorSource>[
  WizardMirrorSource(
    id: 'github',
    name: 'GitHub (官方)',
    repoUrl: 'https://github.com/MoFox-Studio/Neo-MoFox.git',
    eulaUrl:
        'https://raw.githubusercontent.com/MoFox-Studio/Neo-MoFox/main/eula.md',
    region: '全球',
  ),
  WizardMirrorSource(
    id: 'ghproxy',
    name: 'GHProxy 加速',
    repoUrl: 'https://ghfast.top/https://github.com/MoFox-Studio/Neo-MoFox.git',
    eulaUrl:
        'https://ghfast.top/https://raw.githubusercontent.com/MoFox-Studio/Neo-MoFox/main/eula.md',
    region: '中国大陆',
  ),
  WizardMirrorSource(
    id: 'ikun',
    name: 'GitHub 代理加速',
    repoUrl:
        'https://github.ikun114.top/https://github.com/MoFox-Studio/Neo-MoFox.git',
    eulaUrl:
        'https://github.ikun114.top/https://raw.githubusercontent.com/MoFox-Studio/Neo-MoFox/main/eula.md',
    region: '中国大陆',
  ),
];

WizardMirrorSource wizardMirrorSourceFor(String id) {
  for (final source in wizardMirrorSources) {
    if (source.id == id) return source;
  }
  return wizardMirrorSources.first;
}
