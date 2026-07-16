import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('xterm extracts wrapped selection text without adding a newline', () {
    final terminal = Terminal()
      ..resize(5, 2, 10, 20)
      ..write('abcdefgh');

    final selection = BufferRangeLine(
      const CellOffset(0, 0),
      const CellOffset(3, 1),
    );

    expect(terminal.buffer.getText(selection), 'abcdefgh');
  });

  test('xterm preserves real line breaks in selected terminal output', () {
    final terminal = Terminal()
      ..resize(10, 3, 10, 20)
      ..write('first\r\nsecond');

    final selection = BufferRangeLine(
      const CellOffset(0, 0),
      const CellOffset(6, 1),
    );

    expect(terminal.buffer.getText(selection), 'first\nsecond');
  });
}
