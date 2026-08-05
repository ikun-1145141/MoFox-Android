import 'dart:convert';

enum TomlTokenKind {
  comment,
  key,
  table,
  string,
  number,
  boolean,
  dateTime,
  punctuation,
  invalid,
}

class TomlToken {
  const TomlToken({
    required this.kind,
    required this.start,
    required this.end,
  });

  final TomlTokenKind kind;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TomlToken &&
          kind == other.kind &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => Object.hash(kind, start, end);
}

class TomlTokenization {
  const TomlTokenization({
    required this.tokens,
    required this.lineStarts,
    required this.utf8ByteLength,
    required this.isComplete,
  });

  final List<TomlToken> tokens;
  final List<int> lineStarts;
  final int utf8ByteLength;
  final bool isComplete;
}

enum _LexMode {
  normal,
  basicString,
  literalString,
  multilineBasicString,
  multilineLiteralString,
}

enum _LineContext { key, value }

class TomlTokenizer {
  const TomlTokenizer();

  TomlTokenization tokenize(String source) {
    final scanner = _TomlScanner(source);
    return scanner.scan();
  }
}

class _TomlScanner {
  _TomlScanner(this.source);

  final String source;
  final List<TomlToken> _tokens = <TomlToken>[];
  final List<int> _lineStarts = <int>[0];
  _LexMode _mode = _LexMode.normal;
  _LineContext _context = _LineContext.key;
  TomlTokenKind _stringKind = TomlTokenKind.string;
  int _index = 0;
  int _stringStart = 0;
  var _isComplete = true;

  TomlTokenization scan() {
    while (_index < source.length) {
      switch (_mode) {
        case _LexMode.normal:
          _scanNormal();
        case _LexMode.basicString:
          _scanBasicString();
        case _LexMode.literalString:
          _scanLiteralString();
        case _LexMode.multilineBasicString:
          _scanMultilineBasicString();
        case _LexMode.multilineLiteralString:
          _scanMultilineLiteralString();
      }
    }
    if (_mode != _LexMode.normal) {
      _add(_stringKind, _stringStart, source.length);
      _isComplete = false;
    }
    return TomlTokenization(
      tokens: List<TomlToken>.unmodifiable(_tokens),
      lineStarts: List<int>.unmodifiable(_lineStarts),
      utf8ByteLength: utf8.encode(source).length,
      isComplete: _isComplete,
    );
  }

  void _scanNormal() {
    final char = source.codeUnitAt(_index);
    if (_isHorizontalWhitespace(char)) {
      _index++;
      return;
    }
    if (_isNewlineAt(_index)) {
      _consumeNewline();
      _context = _LineContext.key;
      return;
    }
    if (char == _hash) {
      final start = _index++;
      while (_index < source.length && !_isNewlineAt(_index)) {
        _index++;
      }
      _add(TomlTokenKind.comment, start, _index);
      return;
    }
    if (_context == _LineContext.key && char == _leftBracket) {
      _scanTableHeader();
      return;
    }
    if (char == _doubleQuote || char == _singleQuote) {
      _beginString(
          char,
          _context == _LineContext.key
              ? TomlTokenKind.key
              : TomlTokenKind.string);
      return;
    }
    if (_context == _LineContext.key) {
      _scanKey();
      return;
    }
    _scanValue();
  }

  void _scanTableHeader() {
    final start = _index;
    final arrayTable = _matches(_index, '[[');
    final closing = arrayTable ? ']]' : ']';
    _index += arrayTable ? 2 : 1;
    var mode = _LexMode.normal;
    var escaped = false;
    while (_index < source.length && !_isNewlineAt(_index)) {
      if (mode == _LexMode.normal && _matches(_index, closing)) {
        _index += closing.length;
        _add(TomlTokenKind.table, start, _index);
        while (_index < source.length &&
            _isHorizontalWhitespace(source.codeUnitAt(_index))) {
          _index++;
        }
        if (_index < source.length &&
            !_isNewlineAt(_index) &&
            source.codeUnitAt(_index) != _hash) {
          final invalidStart = _index;
          while (_index < source.length && !_isNewlineAt(_index)) {
            _index++;
          }
          _add(TomlTokenKind.invalid, invalidStart, _index);
        }
        _context = _LineContext.value;
        return;
      }
      final char = source.codeUnitAt(_index);
      if (mode == _LexMode.normal && char == _doubleQuote) {
        mode = _LexMode.basicString;
      } else if (mode == _LexMode.normal && char == _singleQuote) {
        mode = _LexMode.literalString;
      } else if (mode == _LexMode.basicString) {
        if (char == _backslash && !escaped) {
          escaped = true;
          _index++;
          continue;
        }
        if (char == _doubleQuote && !escaped) mode = _LexMode.normal;
        escaped = false;
      } else if (mode == _LexMode.literalString && char == _singleQuote) {
        mode = _LexMode.normal;
      }
      _index++;
    }
    _add(TomlTokenKind.invalid, start, _index);
    _isComplete = false;
  }

  void _scanKey() {
    final char = source.codeUnitAt(_index);
    if (char == _equals) {
      _add(TomlTokenKind.punctuation, _index, ++_index);
      _context = _LineContext.value;
      return;
    }
    if (char == _dot) {
      _add(TomlTokenKind.punctuation, _index, ++_index);
      return;
    }
    if (_isBareKeyChar(char)) {
      final start = _index++;
      while (
          _index < source.length && _isBareKeyChar(source.codeUnitAt(_index))) {
        _index++;
      }
      _add(TomlTokenKind.key, start, _index);
      return;
    }
    final start = _index++;
    while (_index < source.length &&
        !_isHorizontalWhitespace(source.codeUnitAt(_index)) &&
        !_isNewlineAt(_index) &&
        source.codeUnitAt(_index) != _equals &&
        source.codeUnitAt(_index) != _dot) {
      _index++;
    }
    _add(TomlTokenKind.invalid, start, _index);
  }

  void _scanValue() {
    final char = source.codeUnitAt(_index);
    if (_isPunctuation(char)) {
      _add(TomlTokenKind.punctuation, _index, ++_index);
      return;
    }
    final start = _index++;
    while (_index < source.length) {
      final next = source.codeUnitAt(_index);
      if (_isHorizontalWhitespace(next) ||
          _isNewlineAt(_index) ||
          next == _hash ||
          _isPunctuation(next) ||
          next == _doubleQuote ||
          next == _singleQuote) {
        break;
      }
      _index++;
    }
    final value = source.substring(start, _index);
    _add(_classifyBareValue(value), start, _index);
  }

  void _beginString(int quote, TomlTokenKind kind) {
    _stringStart = _index;
    _stringKind = kind;
    if (quote == _doubleQuote && _matches(_index, '"""')) {
      _mode = _LexMode.multilineBasicString;
      _index += 3;
    } else if (quote == _singleQuote && _matches(_index, "'''")) {
      _mode = _LexMode.multilineLiteralString;
      _index += 3;
    } else {
      _mode =
          quote == _doubleQuote ? _LexMode.basicString : _LexMode.literalString;
      _index++;
    }
  }

  void _scanBasicString() {
    while (_index < source.length) {
      if (_isNewlineAt(_index)) {
        _add(TomlTokenKind.invalid, _stringStart, _index);
        _mode = _LexMode.normal;
        _isComplete = false;
        return;
      }
      final char = source.codeUnitAt(_index);
      if (char == _backslash) {
        _index += _index + 1 < source.length ? 2 : 1;
      } else if (char == _doubleQuote) {
        _index++;
        _add(_stringKind, _stringStart, _index);
        _mode = _LexMode.normal;
        return;
      } else {
        _index++;
      }
    }
  }

  void _scanLiteralString() {
    while (_index < source.length) {
      if (_isNewlineAt(_index)) {
        _add(TomlTokenKind.invalid, _stringStart, _index);
        _mode = _LexMode.normal;
        _isComplete = false;
        return;
      }
      if (source.codeUnitAt(_index) == _singleQuote) {
        _index++;
        _add(_stringKind, _stringStart, _index);
        _mode = _LexMode.normal;
        return;
      }
      _index++;
    }
  }

  void _scanMultilineBasicString() {
    while (_index < source.length) {
      if (_matches(_index, '"""') && !_isEscaped(_index)) {
        var quoteCount = 3;
        while (_index + quoteCount < source.length &&
            source.codeUnitAt(_index + quoteCount) == _doubleQuote) {
          quoteCount++;
        }
        _index += quoteCount.clamp(3, 5);
        _add(_stringKind, _stringStart, _index);
        _mode = _LexMode.normal;
        return;
      }
      if (_isNewlineAt(_index)) {
        _consumeNewline();
      } else if (source.codeUnitAt(_index) == _backslash) {
        if (_index + 1 < source.length && _isNewlineAt(_index + 1)) {
          _index++;
          _consumeNewline();
          while (_index < source.length &&
              (_isHorizontalWhitespace(source.codeUnitAt(_index)) ||
                  _isNewlineAt(_index))) {
            if (_isNewlineAt(_index)) {
              _consumeNewline();
            } else {
              _index++;
            }
          }
        } else {
          _index += _index + 1 < source.length ? 2 : 1;
        }
      } else {
        _index++;
      }
    }
  }

  void _scanMultilineLiteralString() {
    while (_index < source.length) {
      if (_matches(_index, "'''")) {
        var quoteCount = 3;
        while (_index + quoteCount < source.length &&
            source.codeUnitAt(_index + quoteCount) == _singleQuote) {
          quoteCount++;
        }
        _index += quoteCount.clamp(3, 5);
        _add(_stringKind, _stringStart, _index);
        _mode = _LexMode.normal;
        return;
      }
      if (_isNewlineAt(_index)) {
        _consumeNewline();
      } else {
        _index++;
      }
    }
  }

  bool _isEscaped(int at) {
    var backslashes = 0;
    var cursor = at - 1;
    while (cursor >= 0 && source.codeUnitAt(cursor) == _backslash) {
      backslashes++;
      cursor--;
    }
    return backslashes.isOdd;
  }

  void _consumeNewline() {
    if (source.codeUnitAt(_index) == _carriageReturn &&
        _index + 1 < source.length &&
        source.codeUnitAt(_index + 1) == _lineFeed) {
      _index += 2;
    } else {
      _index++;
    }
    _lineStarts.add(_index);
  }

  bool _isNewlineAt(int at) {
    final char = source.codeUnitAt(at);
    return char == _lineFeed || char == _carriageReturn;
  }

  bool _matches(int at, String pattern) =>
      at + pattern.length <= source.length && source.startsWith(pattern, at);

  void _add(TomlTokenKind kind, int start, int end) {
    if (end > start) {
      _tokens.add(TomlToken(kind: kind, start: start, end: end));
    }
  }
}

TomlTokenKind _classifyBareValue(String value) {
  if (value == 'true' || value == 'false') return TomlTokenKind.boolean;
  if (_dateTimePattern.hasMatch(value)) return TomlTokenKind.dateTime;
  if (_numberPattern.hasMatch(value)) return TomlTokenKind.number;
  return TomlTokenKind.invalid;
}

bool _isHorizontalWhitespace(int char) => char == _space || char == _tab;

bool _isBareKeyChar(int char) =>
    char >= _upperA && char <= _upperZ ||
    char >= _lowerA && char <= _lowerZ ||
    char >= _zero && char <= _nine ||
    char == _underscore ||
    char == _hyphen;

bool _isPunctuation(int char) =>
    char == _leftBracket ||
    char == _rightBracket ||
    char == _leftBrace ||
    char == _rightBrace ||
    char == _comma;

final RegExp _dateTimePattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}(?:[Tt ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[Zz]|[+-]\d{2}:\d{2})?)?$|^\d{2}:\d{2}:\d{2}(?:\.\d+)?$',
);
final RegExp _numberPattern = RegExp(
  r'^[+-]?(?:(?:0|[1-9](?:_?\d)*)(?:\.(?:\d(?:_?\d)*))?(?:[eE][+-]?\d(?:_?\d)*)?|0x[0-9A-Fa-f](?:_?[0-9A-Fa-f])*|0o[0-7](?:_?[0-7])*|0b[01](?:_?[01])*|inf|nan)$',
);

const int _tab = 0x09;
const int _lineFeed = 0x0A;
const int _carriageReturn = 0x0D;
const int _space = 0x20;
const int _hash = 0x23;
const int _doubleQuote = 0x22;
const int _singleQuote = 0x27;
const int _comma = 0x2C;
const int _hyphen = 0x2D;
const int _dot = 0x2E;
const int _zero = 0x30;
const int _nine = 0x39;
const int _equals = 0x3D;
const int _upperA = 0x41;
const int _upperZ = 0x5A;
const int _leftBracket = 0x5B;
const int _backslash = 0x5C;
const int _rightBracket = 0x5D;
const int _underscore = 0x5F;
const int _lowerA = 0x61;
const int _lowerZ = 0x7A;
const int _leftBrace = 0x7B;
const int _rightBrace = 0x7D;
