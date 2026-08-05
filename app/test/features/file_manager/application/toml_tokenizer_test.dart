import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/file_manager/application/toml_tokenizer.dart';

void main() {
  const tokenizer = TomlTokenizer();

  TomlTokenization tokenize(String source) => tokenizer.tokenize(source);

  test('empty source produces no tokens and is complete', () {
    final result = tokenize('');
    expect(result.tokens, isEmpty);
    expect(result.isComplete, isTrue);
    expect(result.utf8ByteLength, 0);
  });

  test('comment only', () {
    const source = '# this is a comment';
    final result = tokenize(source);
    expect(result.tokens, hasLength(1));
    final token = result.tokens.single;
    expect(token.kind, TomlTokenKind.comment);
    expect(token.start, 0);
    expect(token.end, source.length);
  });

  test('bare key = integer value', () {
    const source = 'port = 8080';
    final result = tokenize(source);
    final kinds = result.tokens.map((t) => t.kind).toList();
    expect(kinds, contains(TomlTokenKind.key));
    expect(kinds, contains(TomlTokenKind.number));
    // = 号
    final punctuation = result.tokens
        .where((t) => t.kind == TomlTokenKind.punctuation)
        .toList();
    expect(punctuation, hasLength(1));
  });

  test('table header', () {
    const source = '[server]';
    final result = tokenize(source);
    final kinds = result.tokens.map((t) => t.kind).toList();
    expect(kinds, contains(TomlTokenKind.table));
    // [server] 应至少包含一个 table token；方括号是否单独成 token 取决于实现。
    expect(result.tokens, isNotEmpty);
  });

  test('basic string value', () {
    const source = 'name = "MoFox"';
    final result = tokenize(source);
    final kinds = result.tokens.map((t) => t.kind).toList();
    expect(kinds, contains(TomlTokenKind.string));
  });

  test('literal string value', () {
    const source = "path = '/usr/bin'";
    final result = tokenize(source);
    final kinds = result.tokens.map((t) => t.kind).toList();
    expect(kinds, contains(TomlTokenKind.string));
  });

  test('boolean values', () {
    const source = 'enabled = true\ndisabled = false';
    final result = tokenize(source);
    final kinds = result.tokens.map((t) => t.kind).toList();
    expect(kinds, contains(TomlTokenKind.boolean));
  });

  test('line starts are tracked', () {
    const source = 'a = 1\nb = 2\nc = 3';
    final result = tokenize(source);
    // 3 行 => 至少 3 个起点（索引 0 + 两个换行后）
    expect(result.lineStarts.length, greaterThanOrEqualTo(3));
    expect(result.lineStarts.first, 0);
  });

  test('utf8 byte length for non-ascii content', () {
    const source = '# 中文注释';
    final result = tokenize(source);
    // 中文字符占 3 字节
    expect(result.utf8ByteLength, greaterThan(source.length));
  });

  test('multiline basic string', () {
    const source = 'description = """\nhello\nworld\n"""';
    final result = tokenize(source);
    final kinds = result.tokens.map((t) => t.kind).toList();
    expect(kinds, contains(TomlTokenKind.string));
  });
}
