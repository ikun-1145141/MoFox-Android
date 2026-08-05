import 'package:meta/meta.dart';

/// 经过校验的、相对于命名 rootfs 作用域的不可变路径。
@immutable
class RootfsRelativePath {
  RootfsRelativePath(Iterable<String> segments)
      : segments = List<String>.unmodifiable(segments) {
    for (final segment in this.segments) {
      _validateSegment(segment);
    }
  }

  const RootfsRelativePath.root() : segments = const <String>[];

  final List<String> segments;

  bool get isRoot => segments.isEmpty;
  String get name => segments.lastOrNull ?? '';
  String get displayPath => isRoot ? '/' : '/${segments.join('/')}';

  RootfsRelativePath get parent =>
      isRoot ? this : RootfsRelativePath(segments.take(segments.length - 1));

  RootfsRelativePath child(String name) {
    _validateSegment(name);
    return RootfsRelativePath(<String>[...segments, name]);
  }

  RootfsRelativePath prefix(int segmentCount) {
    if (segmentCount < 0 || segmentCount > segments.length) {
      throw RangeError.range(segmentCount, 0, segments.length);
    }
    return RootfsRelativePath(segments.take(segmentCount));
  }

  List<String> toChannelList() => List<String>.of(segments, growable: false);

  static void _validateSegment(String segment) {
    if (segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.contains('/') ||
        segment.contains(r'\') ||
        segment.contains('\u0000')) {
      throw const FormatException('非法相对路径段');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RootfsRelativePath && _segmentsEqual(segments, other.segments);

  @override
  int get hashCode => Object.hashAll(segments);

  @override
  String toString() => displayPath;
}

bool _segmentsEqual(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
