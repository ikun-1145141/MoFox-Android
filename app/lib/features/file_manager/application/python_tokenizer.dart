import 'dart:convert';

/// Python 词法 token 类型。
enum PythonTokenKind {
  comment,
  keyword,
  builtin,
  string,
  number,
  decorator,
  operator,
  punctuation,
  identifier,
  whitespace,
}

/// Python 词法 token。
class PythonToken {
  const PythonToken({
    required this.kind,
    required this.start,
    required this.end,
  });

  final PythonTokenKind kind;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PythonToken &&
          kind == other.kind &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => Object.hash(kind, start, end);
}

/// Python 词法分析结果。
class PythonTokenization {
  const PythonTokenization({
    required this.tokens,
    required this.lineStarts,
    required this.utf8ByteLength,
    required this.isComplete,
  });

  final List<PythonToken> tokens;
  final List<int> lineStarts;
  final int utf8ByteLength;
  final bool isComplete;
}

/// Python 关键字。
const Set<String> _pythonKeywords = {
  'False',
  'None',
  'True',
  'and',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'class',
  'continue',
  'def',
  'del',
  'elif',
  'else',
  'except',
  'finally',
  'for',
  'from',
  'global',
  'if',
  'import',
  'in',
  'is',
  'lambda',
  'nonlocal',
  'not',
  'or',
  'pass',
  'raise',
  'return',
  'try',
  'while',
  'with',
  'yield',
  'match',
  'case',
};

/// Python 内置常量与常用内置函数。
const Set<String> _pythonBuiltins = {
  'self',
  'cls',
  'abs',
  'all',
  'any',
  'ascii',
  'bin',
  'bool',
  'bytearray',
  'bytes',
  'callable',
  'chr',
  'classmethod',
  'compile',
  'complex',
  'delattr',
  'dict',
  'dir',
  'divmod',
  'enumerate',
  'eval',
  'exec',
  'filter',
  'float',
  'format',
  'frozenset',
  'getattr',
  'globals',
  'hasattr',
  'hash',
  'help',
  'hex',
  'id',
  'input',
  'int',
  'isinstance',
  'issubclass',
  'iter',
  'len',
  'list',
  'locals',
  'map',
  'max',
  'memoryview',
  'min',
  'next',
  'object',
  'oct',
  'open',
  'ord',
  'pow',
  'print',
  'property',
  'range',
  'repr',
  'reversed',
  'round',
  'set',
  'setattr',
  'slice',
  'sorted',
  'staticmethod',
  'str',
  'sum',
  'super',
  'tuple',
  'type',
  'vars',
  'zip',
  '__import__',
  'Exception',
  'ValueError',
  'TypeError',
  'KeyError',
  'IndexError',
  'AttributeError',
  'RuntimeError',
  'StopIteration',
  'ImportError',
  'FileNotFoundError',
  'PermissionError',
  'OSError',
  'IOError',
  'ArithmeticError',
  'ZeroDivisionError',
  'OverflowError',
  'NotImplementedError',
  'RecursionError',
  'NameError',
  'UnboundLocalError',
  'UnicodeError',
  'UnicodeDecodeError',
  'UnicodeEncodeError',
  'KeyboardInterrupt',
  'SystemExit',
  'GeneratorExit',
};

/// Python 词法扫描器。
///
/// 实用级覆盖：注释、字符串（含三引号、f/r/b 前缀）、关键字、数字、装饰器、
/// 运算符与标点。不做完整 AST 级别的语义分析，优先保证大文件下的性能与
/// 视觉一致性。
class PythonTokenizer {
  const PythonTokenizer();

  PythonTokenization tokenize(String source) {
    final scanner = _PythonScanner(source);
    return scanner.scan();
  }
}

class _PythonScanner {
  _PythonScanner(this.source);

  final String source;
  final List<PythonToken> _tokens = <PythonToken>[];
  final List<int> _lineStarts = <int>[0];
  var _isComplete = true;

  PythonTokenization scan() {
    var i = 0;
    while (i < source.length) {
      final char = source.codeUnitAt(i);

      // 换行
      if (char == _newline) {
        _lineStarts.add(i + 1);
        i++;
        continue;
      }
      if (char == _carriageReturn &&
          i + 1 < source.length &&
          source.codeUnitAt(i + 1) == _newline) {
        _lineStarts.add(i + 2);
        i += 2;
        continue;
      }

      // 空白
      if (_isWhitespace(char)) {
        final start = i;
        while (i < source.length && _isWhitespace(source.codeUnitAt(i))) {
          i++;
        }
        _add(PythonTokenKind.whitespace, start, i);
        continue;
      }

      // 注释
      if (char == _hash) {
        final start = i;
        while (i < source.length && source.codeUnitAt(i) != _newline) {
          i++;
        }
        _add(PythonTokenKind.comment, start, i);
        continue;
      }

      // 装饰器 @name
      if (char == _at && (i == 0 || _isLineStart(i - 1))) {
        final start = i;
        i++;
        while (i < source.length && _isIdentChar(source.codeUnitAt(i))) {
          i++;
        }
        _add(PythonTokenKind.decorator, start, i);
        continue;
      }

      // 字符串前缀 f/r/b/u（如 f"..." r'''...''' b"..."）
      final stringStart = _tryScanString(i);
      if (stringStart != null) {
        if (!stringStart.complete) _isComplete = false;
        _add(PythonTokenKind.string, stringStart.start, stringStart.end);
        i = stringStart.end;
        continue;
      }

      // 数字
      if (_isDigit(char)) {
        final end = _scanNumber(i);
        _add(PythonTokenKind.number, i, end);
        i = end;
        continue;
      }

      // 标识符 / 关键字 / 内建
      if (_isIdentStart(char)) {
        final start = i;
        while (i < source.length && _isIdentChar(source.codeUnitAt(i))) {
          i++;
        }
        final word = source.substring(start, i);
        final kind = _classifyWord(word);
        _add(kind, start, i);
        continue;
      }

      // 运算符
      final opLen = _operatorLength(i);
      if (opLen > 0) {
        _add(PythonTokenKind.operator, i, i + opLen);
        i += opLen;
        continue;
      }

      // 其他标点
      _add(PythonTokenKind.punctuation, i, i + 1);
      i++;
    }
    return PythonTokenization(
      tokens: List<PythonToken>.unmodifiable(_tokens),
      lineStarts: List<int>.unmodifiable(_lineStarts),
      utf8ByteLength: utf8.encode(source).length,
      isComplete: _isComplete,
    );
  }

  void _add(PythonTokenKind kind, int start, int end) {
    if (end > start) {
      _tokens.add(PythonToken(kind: kind, start: start, end: end));
    }
  }

  bool _isLineStart(int index) {
    if (index < 0) return true;
    final char = source.codeUnitAt(index);
    return char == _newline || char == _carriageReturn;
  }

  _StringScanResult? _tryScanString(int i) {
    final start = i;
    var prefixEnd = i;

    // 字符串前缀（最多 2 个字符，如 fr, rb, br）
    while (prefixEnd < i + 2 && prefixEnd < source.length) {
      final c = source.codeUnitAt(prefixEnd);
      final lower = c | 0x20; // 转小写
      if (lower == _f || lower == _r || lower == _b || lower == _u) {
        prefixEnd++;
      } else {
        break;
      }
    }

    if (prefixEnd >= source.length) return null;
    final quote = source.codeUnitAt(prefixEnd);
    if (quote != _doubleQuote && quote != _singleQuote) {
      // 前缀字符后面不是引号，说明前缀其实是标识符开头，不是字符串。
      return null;
    }

    // 三引号？
    if (prefixEnd + 2 < source.length &&
        source.codeUnitAt(prefixEnd + 1) == quote &&
        source.codeUnitAt(prefixEnd + 2) == quote) {
      final end = _scanTripleQuoted(prefixEnd + 3, quote);
      return _StringScanResult(start, end, end < source.length);
    }

    // 单引号字符串
    var j = prefixEnd + 1;
    while (j < source.length) {
      final c = source.codeUnitAt(j);
      if (c == _backslash) {
        j += 2;
        continue;
      }
      if (c == _newline) {
        // 未闭合的单引号字符串到行尾结束（Python 实际会报错，但高亮这里收尾即可）
        return _StringScanResult(start, j, false);
      }
      if (c == quote) {
        j++;
        return _StringScanResult(start, j, true);
      }
      j++;
    }
    return _StringScanResult(start, j, false);
  }

  int _scanTripleQuoted(int start, int quote) {
    var j = start;
    while (j < source.length) {
      final c = source.codeUnitAt(j);
      if (c == _backslash) {
        j += 2;
        continue;
      }
      if (c == quote &&
          j + 2 < source.length &&
          source.codeUnitAt(j + 1) == quote &&
          source.codeUnitAt(j + 2) == quote) {
        return j + 3;
      }
      if (c == quote && j + 2 >= source.length) {
        // 文件末尾不完整的三引号
        return source.length;
      }
      j++;
    }
    return source.length;
  }

  int _scanNumber(int start) {
    var i = start;
    // 0x / 0o / 0b 前缀
    if (source.codeUnitAt(i) == _0 && i + 1 < source.length) {
      final next = source.codeUnitAt(i + 1) | 0x20;
      if (next == _x || next == _o || next == _b) {
        i += 2;
        while (i < source.length && _isHexDigit(source.codeUnitAt(i))) {
          i++;
        }
        return i;
      }
    }
    // 十进制（含小数与指数）
    while (i < source.length && _isDigit(source.codeUnitAt(i))) {
      i++;
    }
    if (i < source.length &&
        source.codeUnitAt(i) == _dot &&
        i + 1 < source.length &&
        _isDigit(source.codeUnitAt(i + 1))) {
      i++;
      while (i < source.length && _isDigit(source.codeUnitAt(i))) {
        i++;
      }
    }
    if (i < source.length) {
      final c = source.codeUnitAt(i) | 0x20;
      if (c == _e) {
        i++;
        if (i < source.length) {
          final sign = source.codeUnitAt(i);
          if (sign == _plus || sign == _minus) i++;
        }
        while (i < source.length && _isDigit(source.codeUnitAt(i))) {
          i++;
        }
      }
    }
    // 数字后的 j 后缀（复数字面量）
    if (i < source.length && (source.codeUnitAt(i) | 0x20) == _j) {
      i++;
    }
    return i;
  }

  int _operatorLength(int i) {
    // 优先匹配双字符运算符
    if (i + 1 < source.length) {
      final two = source.substring(i, i + 2);
      if (_twoCharOps.contains(two)) return 2;
    }
    final c = source.codeUnitAt(i);
    if (_singleCharOps.contains(c)) return 1;
    return 0;
  }

  PythonTokenKind _classifyWord(String word) {
    if (_pythonKeywords.contains(word)) return PythonTokenKind.keyword;
    if (_pythonBuiltins.contains(word)) return PythonTokenKind.builtin;
    return PythonTokenKind.identifier;
  }

  bool _isWhitespace(int c) => c == _space || c == _tab;
  bool _isDigit(int c) => c >= _0 && c <= _9;
  bool _isHexDigit(int c) =>
      (c >= _0 && c <= _9) || (c >= _a && c <= _f) || (c >= _A && c <= _F);
  bool _isIdentStart(int c) =>
      c == _underscore || (c >= _a && c <= _z) || (c >= _A && c <= _Z);
  bool _isIdentChar(int c) => _isIdentStart(c) || _isDigit(c);
}

class _StringScanResult {
  const _StringScanResult(this.start, this.end, this.complete);
  final int start;
  final int end;
  final bool complete;
}

// ASCII 码点常量
const int _newline = 0x0A;
const int _carriageReturn = 0x0D;
const int _space = 0x20;
const int _tab = 0x09;
const int _hash = 0x23; // #
const int _at = 0x40; // @
const int _doubleQuote = 0x22; // "
const int _singleQuote = 0x27; // '
const int _backslash = 0x5C; // \
const int _underscore = 0x5F; // _
const int _0 = 0x30;
const int _9 = 0x39;
const int _a = 0x61;
const int _f = 0x66;
const int _z = 0x7A;
const int _A = 0x41;
const int _F = 0x46;
const int _Z = 0x5A;
const int _b = 0x62;
const int _e = 0x65;
const int _j = 0x6A;
const int _o = 0x6F;
const int _r = 0x72;
const int _u = 0x75;
const int _x = 0x78;
const int _dot = 0x2E; // .
const int _plus = 0x2B; // +
const int _minus = 0x2D; // -

const Set<String> _twoCharOps = {
  '==',
  '!=',
  '<=',
  '>=',
  '+=',
  '-=',
  '*=',
  '/=',
  '%=',
  '//',
  '**',
  '->',
  ':=',
  '>>',
  '<<',
  '&=',
  '|=',
  '^=',
  '@=',
};

const Set<int> _singleCharOps = {
  0x2B, // +
  0x2D, // -
  0x2A, // *
  0x2F, // /
  0x25, // %
  0x3D, // =
  0x3C, // <
  0x3E, // >
  0x26, // &
  0x7C, // |
  0x5E, // ^
  0x7E, // ~
};
