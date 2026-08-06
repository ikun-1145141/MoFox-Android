/// 支持高亮或渲染的文本文件语言类别。
///
/// 二进制文件不在编辑器范围内，由调用方在进入编辑器前自行判定。
enum TextFileLanguage {
  /// TOML 配置文件，沿用已有的专用编辑器。
  toml,

  /// Python 源码，启用词法高亮。
  python,

  /// Markdown，支持源码高亮 + 渲染预览切换。
  markdown,

  /// JSON / YAML / INI 等结构化文本，统一作为纯文本高亮键值风格。
  structured,

  /// 普通纯文本，无高亮。
  plain;

  /// 是否具备语法高亮能力。
  bool get supportsHighlight =>
      this == toml || this == python || this == markdown || this == structured;

  /// 是否具备渲染预览能力（当前仅 markdown）。
  bool get supportsPreview => this == markdown;

  /// 展示名称。
  String get displayName => switch (this) {
        TextFileLanguage.toml => 'TOML',
        TextFileLanguage.python => 'Python',
        TextFileLanguage.markdown => 'Markdown',
        TextFileLanguage.structured => '文本',
        TextFileLanguage.plain => '文本',
      };
}

/// 根据文件名判定文本语言类别。
///
/// 判定依据仅基于扩展名，避免在 UI 层读取文件内容做嗅探（成本高且不可靠）。
/// 未匹配到的扩展名返回 [TextFileLanguage.plain]。
TextFileLanguage detectTextFileLanguage(String fileName) {
  final lower = fileName.toLowerCase();
  final dot = lower.lastIndexOf('.');
  if (dot < 0 || dot == lower.length - 1) {
    // 无扩展名或以点结尾，常见于 README / LICENSE 等。
    if (_plainTextBasenames.contains(lower)) return TextFileLanguage.plain;
    return TextFileLanguage.plain;
  }
  final ext = lower.substring(dot + 1);
  return _extensionMap[ext] ?? TextFileLanguage.plain;
}

/// 根据文件大小和扩展名粗略判断是否为可编辑文本文件。
///
/// 超过 [maxBytes] 一律视为不可编辑；命中已知二进制扩展名也视为不可编辑。
bool isLikelyEditableTextFile({
  required String fileName,
  required int sizeBytes,
  int maxBytes = 1024 * 1024,
}) {
  if (sizeBytes > maxBytes) return false;
  final lower = fileName.toLowerCase();
  final dot = lower.lastIndexOf('.');
  if (dot < 0) return true;
  final ext = lower.substring(dot + 1);
  if (_binaryExtensions.contains(ext)) return false;
  return true;
}

const Map<String, TextFileLanguage> _extensionMap = {
  // TOML
  'toml': TextFileLanguage.toml,
  // Python
  'py': TextFileLanguage.python,
  'pyi': TextFileLanguage.python,
  'pyw': TextFileLanguage.python,
  // Markdown
  'md': TextFileLanguage.markdown,
  'markdown': TextFileLanguage.markdown,
  // 结构化配置
  'json': TextFileLanguage.structured,
  'yaml': TextFileLanguage.structured,
  'yml': TextFileLanguage.structured,
  'ini': TextFileLanguage.structured,
  'cfg': TextFileLanguage.structured,
  'conf': TextFileLanguage.structured,
  'properties': TextFileLanguage.structured,
  'sh': TextFileLanguage.structured,
  'bash': TextFileLanguage.structured,
  'env': TextFileLanguage.structured,
  // 纯文本
  'txt': TextFileLanguage.plain,
  'log': TextFileLanguage.plain,
};

const Set<String> _plainTextBasenames = {
  'readme',
  'license',
  'licence',
  'authors',
  'contributors',
  'changelog',
  'notice',
};

/// 常见二进制扩展名，用于阻止进入编辑器。
const Set<String> _binaryExtensions = {
  // 图片
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'tiff', 'tif', 'svg',
  'heic', 'heif',
  // 音视频
  'mp3', 'wav', 'flac', 'aac', 'ogg', 'mp4', 'mkv', 'avi', 'mov', 'webm',
  'm4a', 'm4v', 'wmv', 'flv',
  // 压缩包
  'zip', 'tar', 'gz', 'xz', 'bz2', '7z', 'rar', 'tgz', 'txz', 'tbz2', 'zst',
  // 可执行 / 库
  'exe', 'dll', 'so', 'dylib', 'bin', 'elf', 'o', 'a', 'class', 'jar',
  'dex', 'apk', 'aab', 'ipa',
  // 数据库
  'db', 'sqlite', 'sqlite3', 'db3',
  // 文档
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp',
  // 其他
  'ttf', 'otf', 'woff', 'woff2', 'pem', 'key', 'p12', 'pfx', 'keystore',
  'jks', 'iso', 'img', 'vdi', 'vmdk', 'qcow2',
};
