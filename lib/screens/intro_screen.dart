import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../audio.dart';
import '../ui/pixel_font.dart';
import '../ui/pixel_stage.dart';

/// Thin Undertale-like border: a black gap, then a dim warm line with clipped corners.
void drawPanelBorder(Canvas c, double x, double y, double w, double h, double opacity) {
  final p = Paint()
    ..isAntiAlias = false
    ..color = const Color(0xFF8A6A44).withValues(alpha: 0.8 * opacity);
  final x0 = x - 3, y0 = y - 3, x1 = x + w + 2, y1 = y + h + 2;
  c.drawRect(Rect.fromLTWH(x0 + 1, y0, x1 - x0 - 1, 1), p);
  c.drawRect(Rect.fromLTWH(x0 + 1, y1, x1 - x0 - 1, 1), p);
  c.drawRect(Rect.fromLTWH(x0, y0 + 1, 1, y1 - y0 - 1), p);
  c.drawRect(Rect.fromLTWH(x1, y0 + 1, 1, y1 - y0 - 1), p);
  p.color = const Color(0xFF3A2A1C).withValues(alpha: 0.9 * opacity);
  c.drawRect(Rect.fromLTWH(x - 1, y - 1, w + 2, 1), p);
  c.drawRect(Rect.fromLTWH(x - 1, y + h, w + 2, 1), p);
  c.drawRect(Rect.fromLTWH(x - 1, y - 1, 1, h + 2), p);
  c.drawRect(Rect.fromLTWH(x + w, y - 1, 1, h + 2), p);
}

/// One storybook picture and the lines written beneath it.
class IntroPanel {
  const IntroPanel(this.image, this.pages);
  final String image;
  final List<String> pages;
}

/// Panels are made from art_src/intro/ by tools/art/cut_intro.py (256x142 each, shown 1:1).
const introPanels = [
  IntroPanel('assets/images/intro/panel_01.png', [
    'LONG AGO, TWO PEOPLES SHARED THE WORLD.',
    'THE ROOTKIN TENDED THE SOIL. THE WINDKIN HERDED THE WIND AND THE RAIN.',
    'THE WINDKIN SENT RAIN TO THE FIELDS, AND THE ROOTKIN SHARED THEIR HARVEST.',
  ]),
  IntroPanel('assets/images/intro/panel_02.png', [
    'THEN, ONE YEAR, THE RAIN STOPPED.',
    'THE FIELDS CRACKED. THE WELLS RAN DRY.',
    'AND THE ROOTKIN BEGAN TO WHISPER: "THE WINDKIN ARE HOARDING THE RAIN."',
  ]),
  IntroPanel('assets/images/intro/panel_03.png', [
    'FEAR TURNED TO ANGER, AND ANGER TURNED TO WAR.',
  ]),
  IntroPanel('assets/images/intro/panel_04.png', [
    'AT LAST, THE ROOTKIN MAGES STRUCK THE SKY WITH A GREAT SEAL.',
    'THE WINDKIN WERE LOCKED ABOVE THE CLOUDS, NEVER TO TOUCH THE GROUND AGAIN.',
  ]),
  IntroPanel('assets/images/intro/panel_05.png', [
    '"...AND THAT IS WHY THE RAIN NEVER COMES, LITTLE SPROUT."',
    '"BUT IT IS ONLY A STORY. NOW GO TO SLEEP."',
  ]),
  IntroPanel('assets/images/intro/panel_06.png', [
    'YEARS PASSED. ONLY ONE FIELD WAS LEFT TO US.',
    "I WATERED IT EVERY DAY WITH GRANDMA'S OLD CANTEEN.",
  ]),
  IntroPanel('assets/images/intro/panel_07.png', [
    'ONE NIGHT, SOMETHING GREW IN THE MIDDLE OF THAT FIELD. NOBODY HAD PLANTED IT.',
    'GRANDMA SAID ONLY ONE THING: "DON\'T YOU DARE CLIMB IT."',
  ]),
  IntroPanel('assets/images/intro/panel_08.png', [
    'OF COURSE, I CLIMBED IT.',
    'HIGHER THAN THE BIRDS. HIGHER THAN THE RAIN.',
  ]),
  IntroPanel('assets/images/intro/panel_09.png', [
    'AND WHEN I REACHED THE CLOUDS...',
    'THE VINE SNAPPED BEHIND ME.',
  ]),
];

const _cardText = 'THERE IS NO WAY BACK DOWN.';

enum _Step { fadeIn, text, fadeOut, card }

/// Undertale style opening: black screen, a framed picture that fades in and the
/// story typed out beneath it. Tap / Z / Space / Enter finishes a line or moves on, X skips.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.onFinished});
  final VoidCallback onFinished;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> with SingleTickerProviderStateMixin {
  static const screenW = 480.0; // wide virtual screen, so the panel takes ~53% of the width
  static const _panelX = 112.0, _panelY = 18.0;
  static const _textX = 112.0, _textY = 172.0, _maxChars = 42;
  static const _charsPerSec = 20.0;

  late final Ticker _ticker;
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  final List<ui.Image> _images = [];
  Duration _last = Duration.zero;

  int _panel = 0;
  int _page = 0;
  double _chars = 0;
  double _hold = 0;
  double _alpha = 0;
  double _endT = 0;
  _Step _step = _Step.fadeIn;
  bool _left = false;

  List<String> get _lines => _wrap(introPanels[_panel].pages[_page]);
  int get _pageLen => _lines.fold(0, (s, l) => s + l.length);

  @override
  void initState() {
    super.initState();
    () async {
      for (final p in introPanels) {
        _images.add(await loadAssetImage(p.image));
      }
      if (!mounted) return;
      _ticker = createTicker(_tick)..start();
      Music.play('audio/theme_lullaby.wav');
    }();
  }

  @override
  void dispose() {
    if (_images.length == introPanels.length) _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    switch (_step) {
      case _Step.fadeIn:
        _alpha = (_alpha + dt / 1.2).clamp(0, 1);
        if (_alpha >= 1) _step = _Step.text;
      case _Step.text:
        if (_chars < _pageLen) {
          final before = _chars.floor();
          _chars += dt * _charsPerSec;
          _blipFor(before, _chars.floor(), _lines.join());
        } else {
          _hold += dt;
          if (_hold > 2.4) _nextPage();
        }
      case _Step.fadeOut:
        _alpha = (_alpha - dt / 1.0).clamp(0, 1);
        if (_alpha <= 0) {
          if (_panel < introPanels.length - 1) {
            _panel++;
            _page = 0;
            _chars = 0;
            _hold = 0;
            _step = _Step.fadeIn;
          } else {
            _step = _Step.card;
            _endT = 0;
          }
        }
      case _Step.card:
        final typedBefore = ((_endT - 0.4) * 16).floor();
        _endT += dt;
        _blipFor(typedBefore, ((_endT - 0.4) * 16).floor(), _cardText);
        if (_endT > 6.5) _leave();
    }
    _repaint.value++;
  }

  void _nextPage() {
    _hold = 0;
    if (_page < introPanels[_panel].pages.length - 1) {
      _page++;
      _chars = 0;
    } else {
      _step = _Step.fadeOut;
    }
  }

  void _advance() {
    if (_step == _Step.text) {
      if (_chars < _pageLen) {
        _chars = _pageLen.toDouble();
      } else {
        _nextPage();
      }
    } else if (_step == _Step.card && _endT > 2.5) {
      _leave();
    }
  }

  /// One text blip for each visible letter typed between [from] and [to] (at most one per frame).
  void _blipFor(int from, int to, String text) {
    for (var i = math.max(0, from); i < to && i < text.length; i++) {
      if (text[i] != ' ') {
        Sfx.blip();
        return;
      }
    }
  }

  void _skip() {
    _step = _Step.card;
    _endT = 0;
    _alpha = 0;
  }

  void _leave() {
    if (_left) return;
    _left = true;
    Music.fadeOut();
    widget.onFinished();
  }

  static List<String> _wrap(String text) {
    final lines = <String>[];
    var cur = '';
    for (final w in text.split(' ')) {
      final next = cur.isEmpty ? w : '$cur $w';
      if (next.length > _maxChars && cur.isNotEmpty) {
        lines.add(cur);
        cur = w;
      } else {
        cur = next;
      }
    }
    if (cur.isNotEmpty) lines.add(cur);
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.keyZ) {
          _advance();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.keyX) {
          _skip();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _advance,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: PixelStage(painter: _IntroPainter(this, _repaint), width: screenW),
        ),
      ),
    );
  }
}

class _IntroPainter extends CustomPainter {
  _IntroPainter(this.s, Listenable repaint) : super(repaint: repaint);
  final _IntroScreenState s;
  final Paint _ink = Paint()..isAntiAlias = false;

  @override
  void paint(Canvas c, Size size) {
    c.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    if (s._images.length != introPanels.length) return;
    if (s._step == _Step.card) {
      final a = (s._endT / 1.5).clamp(0.0, 1.0) * (1 - ((s._endT - 5.4) / 1.1).clamp(0.0, 1.0));
      _ink.color = ink.withValues(alpha: a);
      PixelFont.draw(c, _cardText, size.width / 2 - PixelFont.width(_cardText) / 2, size.height / 2 - 4, _ink, progress: (s._endT - 0.4) * 16);
      return;
    }
    final img = s._images[s._panel];
    final a = s._alpha;
    drawPixelImage(c, img, _IntroScreenState._panelX, _IntroScreenState._panelY, a);
    drawPanelBorder(c, _IntroScreenState._panelX, _IntroScreenState._panelY, img.width.toDouble(), img.height.toDouble(), a);
    if (s._step == _Step.text || s._step == _Step.fadeOut) {
      _ink.color = ink.withValues(alpha: s._step == _Step.fadeOut ? a : 1);
      var left = s._chars;
      var y = _IntroScreenState._textY;
      for (final line in s._lines) {
        if (left <= 0) break;
        PixelFont.draw(c, line, _IntroScreenState._textX, y, _ink, progress: left);
        left -= line.length;
        y += 13;
      }
    }
  }

  @override
  bool shouldRepaint(_IntroPainter old) => true;
}
