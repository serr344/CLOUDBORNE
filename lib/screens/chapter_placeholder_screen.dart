import 'package:flutter/material.dart';
import '../ui/pixel_font.dart';
import '../ui/pixel_stage.dart';
import 'title_screen.dart';

/// Shown after the name is chosen, until chapter 1 exists. Tap to return to the title.
class ChapterPlaceholderScreen extends StatelessWidget {
  const ChapterPlaceholderScreen({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pushReplacement(fadeRoute(const TitleScreen())),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: PixelStage(painter: _PlaceholderPainter(name)),
      ),
    );
  }
}

class _PlaceholderPainter extends CustomPainter {
  _PlaceholderPainter(this.name);
  final String name;
  final Paint _ink = Paint()..isAntiAlias = false;

  void _centered(Canvas c, String text, double y, [double scale = 1]) =>
      PixelFont.draw(c, text, 160 - PixelFont.width(text, scale) / 2, y, _ink, sx: scale, sy: scale);

  @override
  void paint(Canvas c, Size size) {
    c.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    _ink.color = ink;
    _centered(c, 'WELCOME, $name.', 40);
    _centered(c, 'CHAPTER 1', 66);
    _centered(c, 'THE MIST LAYER', 82, 2);
    _ink.color = ink.withValues(alpha: 0.5);
    _centered(c, '(COMING SOON - TAP TO RETURN)', 120);
  }

  @override
  bool shouldRepaint(_PlaceholderPainter old) => old.name != name;
}
