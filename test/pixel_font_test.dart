import 'package:cloudborne/ui/pixel_font.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wrap breaks at spaces and keeps every word', () {
    const text = 'THE WINDKIN SENT RAIN TO THE FIELDS, AND THE ROOTKIN SHARED THEIR HARVEST.';
    final lines = PixelFont.wrap(text, 42);
    expect(lines, ['THE WINDKIN SENT RAIN TO THE FIELDS, AND', 'THE ROOTKIN SHARED THEIR HARVEST.']);
    expect(lines.every((l) => l.length <= 42), isTrue);
    expect(lines.join(' '), text);
  });

  test('wrap keeps a word longer than the line on its own line', () {
    expect(PixelFont.wrap('A VERYLONGWORD B', 5), ['A', 'VERYLONGWORD', 'B']);
  });

  test('wrap of empty text is empty', () {
    expect(PixelFont.wrap('', 10), isEmpty);
  });
}
