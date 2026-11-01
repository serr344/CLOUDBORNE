import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../audio.dart';
import '../game_state.dart';
import '../ui/pixel_font.dart';
import '../ui/pixel_stage.dart';

/// What the confirm step says about a name, and whether it may be used.
class _Reaction {
  const _Reaction(this.text, {this.allowed = true});
  final String text;
  final bool allowed;
}

const _defaultReaction = _Reaction('IS THAT WHAT THEY CALL YOU?');

/// Names that get a special answer. Keys are upper case.
const Map<String, _Reaction> _specialNames = {
  'PUS': _Reaction('...THAT NAME IS TAKEN. (SHE IS SHY ABOUT IT.)', allowed: false),
  'GARDENER': _Reaction('...WHO TOLD YOU THAT NAME?', allowed: false),
  'ZEPHYRA': _Reaction('YOU ARE NOT A QUEEN. ...YET?'),
  'GRANDMA': _Reaction('SHE WOULD NOT APPROVE.'),
  'NANA': _Reaction('SHE WOULD NOT APPROVE.'),
  'CUMULUS': _Reaction('THE MAYOR IS FLATTERED. IT IS RAINING SOMEWHERE.'),
  'KUMULUS': _Reaction('THE MAYOR IS FLATTERED. IT IS RAINING SOMEWHERE.'),
  'GURBUZ': _Reaction('THAT NAME WILL ARRIVE A FEW SECONDS LATE.'),
  'CLOUD': _Reaction('VERY FUNNY.'),
  'WATCHER': _Reaction('...'),
};

enum _Phase { pick, confirm, leaving }

/// "The wind asks for your name": the letters ride a slowly turning wind rose. The front letter is
/// the one you take. Arrows / swipe turn it, Z / tap takes a letter, X erases, Enter finishes.
/// Typing on a keyboard turns the rose to that letter and takes it.
class NameScreen extends StatefulWidget {
  const NameScreen({super.key, required this.onDone});
  final ValueChanged<String> onDone;

  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> with SingleTickerProviderStateMixin {
  static const maxLen = 8;
  static const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const n = 26;
  static const cx = 160.0, cy = 96.0, rx = 118.0, ry = 34.0;
  static const eraseX = 28.0, doneX = 268.0, buttonY = 164.0;

  late final Ticker _ticker;
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  double _t = 0;
  Duration _last = Duration.zero;

  String _name = '';
  _Phase _phase = _Phase.pick;

  /// Index of the letter in front; [_rot] eases towards it so the rose turns smoothly.
  int _sel = 0;
  double _rot = 0;
  double _dragAcc = 0;

  /// Recently taken letter flying from the rose into the name.
  double _takeT = 9;
  double _confirmT = 0;
  bool _yes = true;
  double _leaveT = 0;

  _Reaction get _reaction => _specialNames[_name] ?? _defaultReaction;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    _t += dt;
    _takeT += dt;
    // ease the rotation along the shortest way round
    var d = (_sel - _rot) % n;
    if (d > n / 2) d -= n;
    _rot += d * (1 - math.exp(-dt * 12));
    if (_phase == _Phase.confirm) _confirmT += dt;
    if (_phase == _Phase.leaving) {
      _leaveT += dt;
      if (_leaveT > 3.0) {
        _ticker.stop();
        widget.onDone(_name);
      }
    }
    _repaint.value++;
  }

  /// Where letter i sits on the rose right now, and how close to the front it is (0 back .. 1 front).
  (Offset, double) letterPos(int i) {
    final a = (i - _rot) / n * 2 * math.pi + math.pi / 2;
    final front = (math.sin(a) + 1) / 2;
    return (Offset(cx + math.cos(a) * rx, cy + math.sin(a) * ry), front);
  }

  // ------------------------------------------------------------------ input
  void _turn(int by) {
    _sel = (_sel + by) % n;
    Sfx.blip();
  }

  void _take() {
    if (_name.length >= maxLen) return;
    _name += letters[_sel];
    Sfx.blip();
    _takeT = 0;
  }

  void _erase() {
    if (_name.isNotEmpty) _name = _name.substring(0, _name.length - 1);
  }

  void _finish() {
    if (_name.isEmpty) return;
    _phase = _Phase.confirm;
    _confirmT = 0;
    _yes = true;
  }

  void _confirmChoice() {
    if (!_reaction.allowed || !_yes) {
      _phase = _Phase.pick;
      return;
    }
    _phase = _Phase.leaving;
    _leaveT = 0;
    GameState.setPlayerName(_name);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (_phase == _Phase.leaving) return KeyEventResult.handled;
    if (_phase == _Phase.confirm) {
      if (_confirmT < 0.5) return KeyEventResult.handled;
      if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight) {
        _yes = !_yes;
      } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.keyZ || k == LogicalKeyboardKey.space) {
        _confirmChoice();
      } else if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.keyX || k == LogicalKeyboardKey.backspace) {
        _phase = _Phase.pick;
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      _turn(-1);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _turn(1);
    } else if (k == LogicalKeyboardKey.space) {
      _take();
    } else if (k == LogicalKeyboardKey.enter) {
      _finish();
    } else if (k == LogicalKeyboardKey.backspace || k == LogicalKeyboardKey.escape) {
      _erase();
    } else {
      final label = k.keyLabel.toUpperCase();
      if (label.length == 1 && letters.contains(label)) {
        // Z and X are letters too when typed; arrows + Space/Enter/Backspace drive the rose.
        _sel = letters.indexOf(label);
        _take();
      }
    }
    return KeyEventResult.handled;
  }

  void _onTap(Offset p) {
    if (_phase == _Phase.leaving) return;
    if (_phase == _Phase.confirm) {
      if (_confirmT < 0.5) return;
      if (!_reaction.allowed) {
        _phase = _Phase.pick;
        return;
      }
      if ((p.dy - (buttonY - 18)).abs() < 12) {
        _yes = p.dx > 160;
        _confirmChoice();
      }
      return;
    }
    if ((p.dy - (buttonY + 3)).abs() < 10) {
      if (p.dx < eraseX + 50) {
        _erase();
        return;
      }
      if (p.dx > doneX - 20) {
        _finish();
        return;
      }
    }
    // the nearest letter on the front half of the rose
    var best = -1;
    var bestD = 14.0;
    for (var i = 0; i < n; i++) {
      final (o, front) = letterPos(i);
      if (front < 0.35) continue;
      final d = (o - p).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    if (best >= 0) {
      _sel = best;
      _take();
    }
  }

  void _onDrag(DragUpdateDetails d) {
    if (_phase != _Phase.pick) return;
    _dragAcc += d.delta.dx;
    while (_dragAcc.abs() > 22) {
      _turn(_dragAcc > 0 ? -1 : 1);
      _dragAcc -= _dragAcc.sign * 22;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onHorizontalDragUpdate: _onDrag,
        onHorizontalDragEnd: (_) => _dragAcc = 0,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: PixelStage(painter: _NamePainter(this, _repaint), onTap: _onTap),
        ),
      ),
    );
  }
}

class _NamePainter extends CustomPainter {
  _NamePainter(this.s, Listenable repaint) : super(repaint: repaint);
  final _NameScreenState s;
  final Paint _p = Paint()..isAntiAlias = false;
  static const warm = Color(0xFFF6D27A);
  static const dim = Color(0xFF5A6478);

  void _text(Canvas c, String t, double x, double y, Color col, {double scale = 1, bool center = false}) {
    _p.color = col;
    final dx = center ? x - PixelFont.width(t, scale) / 2 : x;
    PixelFont.draw(c, t, dx.roundToDouble(), y.roundToDouble(), _p, sx: scale, sy: scale);
  }

  void _dot(Canvas c, double x, double y, Color col, [double w = 1, double h = 1]) {
    _p.color = col;
    c.drawRect(Rect.fromLTWH(x.roundToDouble(), y.roundToDouble(), w, h), _p);
  }

  @override
  void paint(Canvas c, Size size) {
    c.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    _wind(c);
    switch (s._phase) {
      case _Phase.pick:
        _paintPick(c);
      case _Phase.confirm:
      case _Phase.leaving:
        _paintConfirm(c, size);
    }
  }

  /// Thin streaks of wind crossing the screen.
  void _wind(Canvas c) {
    for (var i = 0; i < 14; i++) {
      final speed = 40 + (i * 37) % 50;
      final len = 6 + (i * 13) % 18;
      final y = 8 + (i * 53) % 164 + math.sin(s._t * 0.8 + i) * 3;
      final x = ((s._t * speed + i * 97) % (360 + len)) - len - 20;
      for (var k = 0; k < len; k++) {
        final a = 0.08 + 0.18 * (k / len);
        _dot(c, x + k, y + math.sin((x + k) * 0.05 + i) * 1.5, ink.withValues(alpha: a));
      }
    }
  }

  /// The name, each letter swaying a little as if in a breeze.
  void _name(Canvas c, String name, double y, double scale, Color col, {double scatter = 0, double pop = 0}) {
    final w = PixelFont.width(name, scale);
    var x = 160 - w / 2;
    for (var i = 0; i < name.length; i++) {
      final sway = math.sin(s._t * 2 + i * 0.9) * 1.2;
      final fx = scatter * (30 + i * 9) + math.sin(scatter * 6 + i) * 10 * scatter;
      final fy = -scatter * scatter * (90 + i * 14);
      final a = (1 - scatter * 1.1).clamp(0.0, 1.0);
      final rise = i == name.length - 1 ? pop * pop * 70 : 0.0;
      _text(c, name[i], x + fx, y + sway + fy + rise, col.withValues(alpha: a), scale: scale);
      x += PixelFont.advance * scale;
    }
  }

  void _paintPick(Canvas c) {
    _text(c, 'THE WIND ASKS FOR YOUR NAME.', 160, 16, ink, center: true);

    // the name in the middle of the rose, with a soft line under it
    final shown = s._name;
    // the newest letter floats up from the rose into place
    _name(c, shown, 30, 2, warm, pop: (1 - s._takeT / 0.25).clamp(0.0, 1.0));
    final lineW = _NameScreenState.maxLen * PixelFont.advance * 2.0;
    for (var k = 0; k < lineW; k += 2) {
      _dot(c, 160 - lineW / 2 + k, 50, ink.withValues(alpha: 0.25));
    }
    if (shown.length < _NameScreenState.maxLen && (s._t * 2).floor().isEven) {
      final cx = 160 + PixelFont.width(shown, 2) / 2 + (shown.isEmpty ? -4 : 3);
      _dot(c, cx, 44, warm, 6, 2);
    }

    // the rose: back letters first, front letters on top
    final order = List.generate(_NameScreenState.n, (i) => i)
      ..sort((a, b) => s.letterPos(a).$2.compareTo(s.letterPos(b).$2));
    // faint ellipse track
    for (var k = 0; k < 120; k++) {
      final a = k / 120 * 2 * math.pi;
      if (k.isEven) {
        _dot(c, _NameScreenState.cx + math.cos(a) * _NameScreenState.rx, _NameScreenState.cy + 4 + math.sin(a) * _NameScreenState.ry,ink.withValues(alpha: 0.06 + 0.1 * (math.sin(a) + 1) / 2));
      }
    }
    for (final i in order) {
      final (o, front) = s.letterPos(i);
      final selected = i == s._sel;
      final scale = front > 0.97 ? 2.0 : 1.0;
      final col = selected
          ? warm
          : Color.lerp(dim.withValues(alpha: 0.35), ink, front * front)!;
      _text(c, _NameScreenState.letters[i], o.dx, o.dy - 3.5 * scale, col, scale: scale, center: true);
    }
    // a small leaf marks the letter in front
    final bob = math.sin(s._t * 4) * 1.5;
    const lx = 160.0, ly = 96.0 + 34 + 12;
    _dot(c, lx - 1, ly + bob, const Color(0xFF7FC86A), 3, 1);
    _dot(c, lx - 2, ly + 1 + bob, const Color(0xFF5AA050), 5, 1);
    _dot(c, lx, ly + 2 + bob, const Color(0xFF3A7A40), 1, 2);

    _text(c, 'ERASE', _NameScreenState.eraseX, _NameScreenState.buttonY, ink.withValues(alpha: 0.7));
    _text(c, 'DONE', _NameScreenState.doneX, _NameScreenState.buttonY,
        s._name.isEmpty ? ink.withValues(alpha: 0.25) : warm);
  }

  void _paintConfirm(Canvas c, Size size) {
    final r = s._reaction;
    final leaving = s._phase == _Phase.leaving;
    final textA = leaving ? (1 - s._leaveT).clamp(0.0, 1.0) : 1.0;
    _text(c, r.text, 160, 34, ink.withValues(alpha: textA), center: true);
    const scale = 2.0;
    final scatter = leaving ? (s._leaveT / 2.2).clamp(0.0, 1.0) : 0.0;
    _name(c, s._name, 74, scale, warm, scatter: scatter);
    if (!leaving) {
      if (r.allowed) {
        _text(c, 'NO', 120, _NameScreenState.buttonY - 18, s._yes ? ink.withValues(alpha: 0.5) : warm, center: true);
        _text(c, 'YES', 200, _NameScreenState.buttonY - 18, s._yes ? warm : ink.withValues(alpha: 0.5), center: true);
      } else {
        _text(c, 'TRY ANOTHER NAME', 160, _NameScreenState.buttonY - 18, warm, center: true);
      }
    } else {
      // everything brightens into cloud light
      final a = ((s._leaveT - 0.8) / 2.0).clamp(0.0, 1.0);
      c.drawRect(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: a));
    }
  }

  @override
  bool shouldRepaint(_NamePainter old) => true;
}
