import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../audio.dart';
import '../battle/battle_screen.dart';
import '../ui/pixel_font.dart';
import '../ui/pixel_stage.dart';
import '../world/chapter1_screen.dart';
import 'intro_screen.dart';
import 'name_screen.dart';

/// Black screen with the game's name. Any key or tap starts the intro.
class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key});

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  void _start() {
    Sfx.init(); // inside the key press / tap, so the browser allows audio
    final nav = Navigator.of(context);
    nav.pushReplacement(fadeRoute(IntroScreen(
      onFinished: () => nav.pushReplacement(fadeRoute(NameScreen(
        onDone: (_) => _toChapter1(nav),
      ))),
    )));
  }

  static void _toChapter1(NavigatorState nav) =>
      nav.pushReplacement(fadeRoute(Chapter1Screen(onExit: () => nav.pushReplacement(fadeRoute(const TitleScreen())))));

  void _startBattle() {
    Sfx.init();
    final nav = Navigator.of(context);
    nav.pushReplacement(fadeRoute(BattleScreen(onExit: () => nav.pushReplacement(fadeRoute(const TitleScreen())))));
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent) {
          // B opens the battle prototype directly (development shortcut)
          if (e.logicalKey == LogicalKeyboardKey.keyB) {
            _startBattle();
          } else {
            _start();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _start,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: PixelStage(painter: _TitlePainter(_blink)),
        ),
      ),
    );
  }
}

class _TitlePainter extends CustomPainter {
  _TitlePainter(this.blink) : super(repaint: blink);
  final Animation<double> blink;
  final Paint _ink = Paint()..isAntiAlias = false;

  @override
  void paint(Canvas c, Size size) {
    c.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    const title = 'CLOUDBORNE';
    _ink.color = ink;
    PixelFont.draw(c, title, 160 - PixelFont.width(title, 3) / 2, 66, _ink, sx: 3, sy: 3);
    if (blink.value < 0.6) {
      const hint = 'PRESS ANY KEY OR TAP';
      PixelFont.draw(c, hint, 160 - PixelFont.width(hint) / 2, 120, _ink);
    }
    const dev = 'B: BATTLE PROTOTYPE';
    _ink.color = ink.withValues(alpha: 0.3);
    PixelFont.draw(c, dev, 160 - PixelFont.width(dev) / 2, 166, _ink);
  }

  @override
  bool shouldRepaint(_TitlePainter old) => true;
}
