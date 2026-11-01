import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../audio.dart';
import '../ui/pixel_font.dart';
import '../ui/pixel_stage.dart';

/// Chapter 1, first area: you wake up on a cloud next to the snapped vine, walk right along a
/// cloud corridor and go through the door at its end.
///
/// Everything comes from assets/images/chapter1: the map picture, a mask of where you can
/// stand (walk.png, opaque = floor), the opened door and the kid's walk frames.
class Chapter1Screen extends StatefulWidget {
  const Chapter1Screen({super.key, required this.onExit});
  final VoidCallback onExit;

  @override
  State<Chapter1Screen> createState() => _Chapter1State();
}

const _screenW = 320.0;
const _screenH = 180.0;

enum _Phase { title, waking, play, talk, door, end }

enum _Dir { down, left, right, up }

class _Chapter1State extends State<Chapter1Screen> with SingleTickerProviderStateMixin {
  final _repaint = ValueNotifier<int>(0);
  final Map<String, ui.Image> img = {};
  late final Ticker _ticker;
  ui.Image? _maskImage;
  List<int> _walk = const [];
  int mapW = 0, mapH = 0;
  double _last = 0;
  double t = 0;

  _Phase phase = _Phase.title;
  double phaseT = 0;

  // the kid: position of his feet, in map pixels
  Offset kid = const Offset(108, 120);
  _Dir dir = _Dir.down;
  double walkT = 0;
  bool moving = false;

  // talking
  List<String> lines = const [];
  int line = 0;
  double chars = 0;
  VoidCallback? afterTalk;

  bool doorOpen = false;
  double hintUntil = 0;

  // touch: a drag from where the finger went down walks; a tap checks / advances
  Offset? touchStart, touchNow;
  bool touchMoved = false;

  // positions in map.png
  static const doorX = 576.0, doorY = 66.0;

  /// The open doorway (inside the stone frame): what the kid can be seen through once he's in.
  static const doorway = Rect.fromLTRB(567, 0, 585, doorY);
  static const enterTime = 1.0;
  Offset enterFrom = Offset.zero;

  /// How much of the kid is still visible while he goes into the light.
  double get kidOpacity => phase == _Phase.end ? 1 - ((phaseT - 0.45) / 0.55).clamp(0.0, 1.0) : 1;
  static const doorSize = Size(28, 38);
  static const vineArea = Rect.fromLTWH(34, 56, 40, 56);

  @override
  void initState() {
    super.initState();
    () async {
      const b = 'assets/images/chapter1';
      for (final n in ['map', 'walk', 'door_open', 'kid_down', 'kid_left', 'kid_right', 'kid_up']) {
        img[n] = await loadAssetImage('$b/$n.png');
      }
      final mask = _maskImage = img['walk']!;
      mapW = mask.width;
      mapH = mask.height;
      _walk = (await mask.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      if (!mounted) return;
      _ticker = createTicker(_tick)..start();
    }();
  }

  @override
  void dispose() {
    if (_maskImage != null) _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  bool get ready => _walk.isNotEmpty;

  void _setPhase(_Phase p) {
    phase = p;
    phaseT = 0;
  }

  // ---------------------------------------------------------------- talking
  void talk(List<String> l, [VoidCallback? after]) {
    lines = l;
    line = 0;
    chars = 0;
    afterTalk = after;
    _setPhase(_Phase.talk);
  }

  String get currentLine => lines[line];

  void advance() {
    if (chars < currentLine.length) {
      chars = currentLine.length.toDouble();
      return;
    }
    if (++line < lines.length) {
      chars = 0;
      return;
    }
    final a = afterTalk;
    afterTalk = null;
    _setPhase(_Phase.play);
    a?.call();
  }

  // ---------------------------------------------------------------- the world
  bool walkable(double x, double y) {
    final ix = x.floor(), iy = y.floor();
    if (ix < 0 || iy < 0 || ix >= mapW || iy >= mapH) return false;
    return _walk[(iy * mapW + ix) * 4 + 3] > 0;
  }

  /// The kid's feet are a small box; all four corners must be on the floor.
  bool canStand(Offset p) =>
      walkable(p.dx - 4, p.dy - 3) && walkable(p.dx + 4, p.dy - 3) && walkable(p.dx - 4, p.dy) && walkable(p.dx + 4, p.dy);

  /// The point just in front of the kid, for checking things.
  Offset get ahead => kid +
      switch (dir) {
        _Dir.down => const Offset(0, 10),
        _Dir.up => const Offset(0, -14),
        _Dir.left => const Offset(-14, -4),
        _Dir.right => const Offset(14, -4),
      };

  bool get atDoor => (kid.dx - doorX).abs() < 12 && kid.dy < doorY + 14;

  void check() {
    if (atDoor && dir == _Dir.up) {
      if (!doorOpen) {
        talk(const ['A door in the middle of the sky.', 'It isn\'t locked.'], _openDoor);
      }
      return;
    }
    if (vineArea.contains(ahead)) {
      talk(const ['The vine you climbed. It snapped clean off.', 'There is no way back down.']);
      return;
    }
    if (dir == _Dir.down && !walkable(ahead.dx, ahead.dy)) {
      talk(const ['Below the cloud there is only more cloud.', 'You can\'t see the fields anymore.']);
    }
  }

  void _openDoor() {
    doorOpen = true;
    Sfx.blip();
    _setPhase(_Phase.door);
  }

  Offset _input() {
    final kb = HardwareKeyboard.instance;
    bool down(List<LogicalKeyboardKey> k) => k.any(kb.isLogicalKeyPressed);
    var v = Offset(
      (down([LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.keyD]) ? 1.0 : 0) -
          (down([LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.keyA]) ? 1.0 : 0),
      (down([LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.keyS]) ? 1.0 : 0) -
          (down([LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.keyW]) ? 1.0 : 0),
    );
    if (v == Offset.zero && touchStart != null && touchNow != null) {
      final d = touchNow! - touchStart!;
      if (d.distance > 6) v = Offset(d.dx.abs() > 3 ? d.dx.sign : 0, d.dy.abs() > 3 ? d.dy.sign : 0);
    }
    return v;
  }

  void _updatePlay(double dt) {
    final v = _input();
    moving = v != Offset.zero;
    if (!moving) {
      walkT = 0;
      return;
    }
    if (v.dy == 0) dir = v.dx > 0 ? _Dir.right : _Dir.left;
    if (v.dx == 0) dir = v.dy > 0 ? _Dir.down : _Dir.up;
    walkT += dt;
    const speed = 90.0;
    final n = v / v.distance * speed * dt;
    // slide along edges: try each axis on its own
    final before = kid;
    if (canStand(kid + Offset(n.dx, 0))) kid += Offset(n.dx, 0);
    if (canStand(kid + Offset(0, n.dy))) kid += Offset(0, n.dy);
    if (kid == before) {
      moving = false; // pushing against an edge: stand still instead of walking in place
      walkT = 0;
    }

    if (doorOpen && atDoor && dir == _Dir.up) {
      enterFrom = kid;
      _setPhase(_Phase.end);
    }
  }

  void _tick(Duration d) {
    final now = d.inMicroseconds / 1e6;
    final dt = (now - _last).clamp(0.0, 0.05);
    _last = now;
    t += dt;
    phaseT += dt;

    switch (phase) {
      case _Phase.title:
        if (phaseT > 3.2) {
          talk(const [
            '...',
            'Something soft under your hands. Cold, like morning fog.',
            'Your arms still ache from the climb.',
          ], () => _setPhase(_Phase.waking));
        }
      case _Phase.waking:
        if (phaseT > 1.4) {
          _setPhase(_Phase.play);
          hintUntil = t + 6;
        }
      case _Phase.talk:
        final before = chars.floor();
        chars = math.min(currentLine.length.toDouble(), chars + dt * 30);
        for (var i = before; i < chars.floor(); i++) {
          if (i.isEven && currentLine[i] != ' ' && currentLine[i] != '.') Sfx.blip();
        }
      case _Phase.play:
        _updatePlay(dt);
      case _Phase.door:
        if (phaseT > 0.4) _setPhase(_Phase.play);
      case _Phase.end:
        // walk smoothly into the doorway (lined up with it), fading into the light
        dir = _Dir.up;
        final u = (phaseT / enterTime).clamp(0.0, 1.0);
        kid = Offset.lerp(enterFrom, const Offset(doorX, doorY - 8), u)!;
        moving = u < 1;
        if (moving) walkT += dt;
    }
    _repaint.value++;
  }

  /// Before the first look around, the screen is still dark (the opening lines play on black).
  bool get stillDark => lines.isNotEmpty && lines.first == '...' && phase == _Phase.talk;

  // ---------------------------------------------------------------- input
  void _press() {
    switch (phase) {
      case _Phase.talk:
        advance();
      case _Phase.play:
        check();
      case _Phase.end:
        if (phaseT > 3.0) widget.onExit();
      case _Phase.title:
      case _Phase.waking:
      case _Phase.door:
        break;
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent || !ready) return KeyEventResult.handled;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.keyZ || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space) {
      _press();
    } else if (k == LogicalKeyboardKey.keyX && phase == _Phase.talk) {
      chars = currentLine.length.toDouble();
    } else if (k == LogicalKeyboardKey.escape) {
      widget.onExit();
    }
    return KeyEventResult.handled;
  }

  void _onTouch(int id, TouchPhase p, Offset at, bool mouse) {
    switch (p) {
      case TouchPhase.down:
        touchStart = at;
        touchNow = at;
        touchMoved = false;
      case TouchPhase.move:
        touchNow = at;
        if (touchStart != null && (at - touchStart!).distance > 6) touchMoved = true;
      case TouchPhase.up:
        if (!touchMoved) _press();
        touchStart = touchNow = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: PixelStage(painter: _WorldPainter(this, _repaint), onTouch: _onTouch),
      ),
    );
  }
}

class _WorldPainter extends CustomPainter {
  _WorldPainter(this.s, Listenable repaint) : super(repaint: repaint);
  final _Chapter1State s;
  final Paint _p = Paint()..isAntiAlias = false;

  void _rect(Canvas c, Rect r, Color col) {
    _p.color = col;
    c.drawRect(r, _p);
  }

  void _text(Canvas c, String text, double x, double y, Color col, {bool center = false, double scale = 1, double progress = double.infinity}) {
    _p.color = col;
    final w = PixelFont.width(text, scale);
    PixelFont.draw(c, text, (center ? x - w / 2 : x).roundToDouble(), y.roundToDouble(), _p, sx: scale, sy: scale, progress: progress);
  }

  void _sub(Canvas c, String name, Rect src, double x, double y) {
    final im = s.img[name];
    if (im == null) return;
    final p = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none;
    c.drawImageRect(im, src, Rect.fromLTWH(x.roundToDouble(), y.roundToDouble(), src.width, src.height), p);
  }

  void _img(Canvas c, String name, double x, double y) {
    final im = s.img[name];
    if (im != null) _sub(c, name, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), x, y);
  }

  @override
  void paint(Canvas c, Size size) {
    _rect(c, Offset.zero & size, Colors.black);
    if (!s.ready) return;

    if (s.phase == _Phase.title) {
      final a = (math.min(s.phaseT, 3.2 - s.phaseT) / 0.7).clamp(0.0, 1.0);
      final col = ink.withValues(alpha: a);
      _text(c, 'CHAPTER 1', 160, 66, col, center: true);
      _text(c, 'THE MIST LAYER', 160, 82, col, center: true, scale: 2);
      return;
    }

    if (!s.stillDark) {
      // the camera follows the kid's exact (not rounded) position, so both move smoothly
      final camX = (s.kid.dx - _screenW / 2).clamp(0.0, s.mapW - _screenW).toDouble();
      final camY = (s.kid.dy - _screenH / 2).clamp(0.0, math.max(0.0, s.mapH - _screenH)).toDouble();
      c.save();
      c.translate(-camX, -camY);
      _img(c, 'map', 0, 0);
      if (s.doorOpen) {
        _img(c, 'door_open', _Chapter1State.doorX - _Chapter1State.doorSize.width / 2, _Chapter1State.doorY - _Chapter1State.doorSize.height);
      }
      if (s.phase == _Phase.end) {
        // once he's past the threshold, the door frame hides whatever is outside the doorway
        c.save();
        c.clipPath(Path()
          ..addRect(_Chapter1State.doorway)
          ..addRect(Rect.fromLTRB(0, _Chapter1State.doorY, s.mapW.toDouble(), s.mapH.toDouble())));
        _kid(c);
        c.restore();
      } else {
        _kid(c);
      }
      c.restore();
    }

    if (s.phase == _Phase.waking) {
      _rect(c, Offset.zero & size, Colors.black.withValues(alpha: (1 - s.phaseT / 1.4).clamp(0.0, 1.0)));
    }
    if (s.phase == _Phase.end) {
      _rect(c, Offset.zero & size, Colors.black.withValues(alpha: ((s.phaseT - 1.0) / 0.9).clamp(0.0, 1.0)));
      if (s.phaseT > 2.1) {
        _text(c, 'TO BE CONTINUED', 160, 80, ink.withValues(alpha: ((s.phaseT - 2.1) / 0.8).clamp(0.0, 1.0)), center: true);
        if (s.phaseT > 3.0 && (s.t * 2).floor().isEven) {
          _text(c, 'PRESS Z OR TAP', 160, 104, ink.withValues(alpha: 0.4), center: true);
        }
      }
    }
    if (s.phase == _Phase.play && s.t < s.hintUntil) {
      final a = (s.hintUntil - s.t).clamp(0.0, 1.0) * 0.6;
      _text(c, 'ARROWS: WALK    Z: CHECK', 160, 168, ink.withValues(alpha: a), center: true);
    }
    if (s.phase == _Phase.talk) _box(c);
  }

  void _kid(Canvas c) {
    final sheet = 'kid_${s.dir.name}';
    final im = s.img[sheet]!;
    final fw = im.width / 4, fh = im.height.toDouble();
    final frame = s.moving ? (s.walkT * 6).floor() % 4 : 0;
    // the frames keep the sheet's own resolution; draw them scaled down, smoothly, so they look
    // exactly like the sheet
    final w = fw / kidScale, h = fh / kidScale;
    final dst = Rect.fromLTWH(s.kid.dx - w / 2, s.kid.dy - h + 1, w, h);
    final p = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(255, 255, 255, s.kidOpacity);
    c.drawImageRect(im, Rect.fromLTWH(frame * fw, 0, fw, fh), dst, p);
  }

  /// Sheet pixels per screen pixel for the kid (the sheet's art pixels are about 7.5 wide).
  static const kidScale = 7.5;

  void _box(Canvas c) {
    const r = Rect.fromLTWH(8, 128, 304, 46);
    _rect(c, r, Colors.black);
    _rect(c, Rect.fromLTWH(r.left, r.top, r.width, 1), ink);
    _rect(c, Rect.fromLTWH(r.left, r.bottom - 1, r.width, 1), ink);
    _rect(c, Rect.fromLTWH(r.left, r.top, 1, r.height), ink);
    _rect(c, Rect.fromLTWH(r.right - 1, r.top, 1, r.height), ink);

    final wrapped = _wrap(s.currentLine, 48);
    var left = s.chars;
    for (var i = 0; i < wrapped.length; i++) {
      _text(c, wrapped[i], r.left + 8, r.top + 8 + i * 11, ink, progress: left);
      left -= wrapped[i].length + 1;
      if (left <= 0) break;
    }
    if (s.chars >= s.currentLine.length && (s.t * 2).floor().isEven) {
      _rect(c, Rect.fromLTWH(r.right - 9, r.bottom - 7, 4, 3), ink);
    }
  }

  static List<String> _wrap(String text, int max) {
    final out = <String>[];
    var line = '';
    for (final w in text.split(' ')) {
      if (line.isEmpty) {
        line = w;
      } else if (line.length + 1 + w.length <= max) {
        line += ' $w';
      } else {
        out.add(line);
        line = w;
      }
    }
    if (line.isNotEmpty) out.add(line);
    return out;
  }

  @override
  bool shouldRepaint(_WorldPainter old) => false;
}
