import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../audio.dart';
import '../game_state.dart';
import '../ui/pixel_font.dart';
import '../ui/pixel_stage.dart';
import 'arena.dart';
import 'monsters.dart';

/// Turn-based battle shared by every enemy, in black and white with a red scarf.
///
/// Your turn: STRIKE (stop the line near the middle; counters add damage), INTERACT (talk,
/// act, spare, flee) or ITEMS. The enemy's turn plays out in the arena on the left: move the
/// kid (position), hold the scarf towards an attack (direction), and raise it just before
/// impact for a PERFECT block that earns a counter (timing).
///
/// Keyboard: WASD moves, arrow keys hold the scarf out that way. Mouse: hold the button to hold
/// the scarf towards the pointer. Touch: left thumb drags to move, right thumb holds the scarf.
///
/// Without a [monster], the prototype first asks which test enemy to fight.
class BattleScreen extends StatefulWidget {
  const BattleScreen({super.key, required this.onExit, this.monster});
  final VoidCallback onExit;
  final Monster Function()? monster;

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

enum _Phase { pick, menu, interact, items, strike, talk, attack, done }

enum _Ending { none, spared, killed, fled, lost }

class _Bit {
  _Bit(this.p, this.v, this.t0, this.color);
  Offset p, v;
  final double t0;
  final Color color;
}

class _Popup {
  _Popup(this.text, this.at, this.t0, this.color);
  final String text;
  final Offset at;
  final double t0;
  final Color color;
}

class _BattleScreenState extends State<BattleScreen> with SingleTickerProviderStateMixin {
  static const screenW = 480.0;
  static const maxHp = 30;
  static const maxCounters = 3;
  static const box = Rect.fromLTWH(14, 36, 308, 176);
  static const enemyAt = Offset(402, 124);
  static const buttons = ['STRIKE', 'INTERACT', 'ITEMS'];
  static const images = [
    'prickle_cup',
    'grumble_gust',
    'windrose_knight',
    'kid',
    'scarf_icon',
    'spear',
    'needle',
    'gust',
    'thorn',
    'warning',
    'windrose_spin',
  ];

  final _rng = math.Random();
  final _repaint = ValueNotifier<int>(0);
  final Map<String, ui.Image> _img = {};
  late final Ticker _ticker;
  double _last = 0;
  double _t = 0;

  late _Phase _phase = widget.monster == null ? _Phase.pick : _Phase.menu;
  _Ending _ending = _Ending.none;
  int _button = 0;
  int _sel = 0;

  late Monster m = (widget.monster ?? PrickleCup.new)();

  /// Text in the arena while you choose (typed out).
  late String _flavor = m.encounter;
  double _flavorChars = 0;

  // talking
  List<BattleLine> _lines = const [];
  int _line = 0;
  double _chars = 0;
  VoidCallback? _after;

  // you
  int hp = maxHp;
  int counters = 0;
  final List<String> items = ['CLOUD BUN', 'CLOUD BUN', 'CANTEEN'];

  // the enemy
  double hitT = -9;
  int lastDmg = 0;
  double deathT = -1;
  double spareT = -1;

  // strike bar
  double _strikeT0 = 0;
  double? _strikeStop;
  static const strikeTime = 1.4;

  // the enemy's turn
  Arena? arena;
  double _attackStart = 0;
  final List<(Offset, double)> _trail = [];
  double _trailT = 0;

  // touch: which finger moves, which one holds the scarf
  int? _moveFinger, _guardFinger;
  Offset _moveStart = Offset.zero, _moveNow = Offset.zero;
  Offset _guardStart = Offset.zero, _guardNow = Offset.zero;
  bool _guardIsMouse = false;

  final List<_Bit> bits = [];
  final List<_Popup> popups = [];
  final List<(double, VoidCallback)> _timers = [];

  /// INTERACT lists the enemy's own actions, then SPARE and FLEE.
  List<String> get interactions => [...m.acts, 'SPARE', 'FLEE'];

  @override
  void initState() {
    super.initState();
    () async {
      for (final n in images) {
        _img[n] = await loadAssetImage('assets/images/battle/$n.png');
      }
      if (!mounted) return;
      _ticker = createTicker(_tick)..start();
    }();
  }

  @override
  void dispose() {
    if (_img.isNotEmpty) _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- helpers
  void _later(double delay, VoidCallback f) => _timers.add((_t + delay, f));

  void _burst(Offset at, int n, {double speed = 50, Color color = const Color(0xFFFFFFFF)}) {
    for (var i = 0; i < n; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final sp = speed * (0.4 + _rng.nextDouble() * 0.6);
      bits.add(_Bit(at, Offset(math.cos(a) * sp, math.sin(a) * sp), _t, color));
    }
  }

  void _popup(String text, Offset at, [Color color = const Color(0xFFFFFFFF)]) => popups.add(_Popup(text, at, _t, color));

  void _talk(List<BattleLine> lines, VoidCallback after) {
    _lines = lines;
    _line = 0;
    _chars = 0;
    _after = after;
    _phase = _Phase.talk;
  }

  BattleLine get currentLine => _lines[_line];

  void _advance() {
    if (_chars < currentLine.text.length) {
      _chars = currentLine.text.length.toDouble();
      return;
    }
    if (_line + 1 >= _lines.length) {
      final a = _after;
      _after = null;
      a?.call();
    } else {
      _line++;
      _chars = 0;
    }
  }

  void _toMenu() {
    _flavor = m.flavor(_rng);
    _flavorChars = 0;
    _phase = _Phase.menu;
  }

  // ---------------------------------------------------------------- choices
  void _pickButton() {
    _sel = 0;
    switch (_button) {
      case 0:
        _strikeT0 = _t;
        _strikeStop = null;
        _phase = _Phase.strike;
      case 1:
        _phase = _Phase.interact;
      default:
        if (items.isNotEmpty) _phase = _Phase.items;
    }
  }

  void _confirm() {
    switch (_phase) {
      case _Phase.pick:
        m = testMonsters[_sel]();
        _flavor = m.encounter;
        _flavorChars = 0;
        _phase = _Phase.menu;
      case _Phase.menu:
        _pickButton();
      case _Phase.interact:
        final a = interactions[_sel];
        if (a == 'SPARE') {
          _spare();
        } else if (a == 'FLEE') {
          _flee();
        } else {
          final was = m.canSpare;
          _talk([
            ...m.act(a),
            if (m.canSpare && !was) BattleLine('${m.title} doesn\'t want to fight anymore.'),
          ], _enemyTurn);
        }
      case _Phase.items:
        _useItem(_sel);
      case _Phase.strike:
        _strike();
      case _Phase.talk:
        _advance();
      case _Phase.done:
        if (_timers.isNotEmpty) return;
        if (_ending == _Ending.lost) {
          Navigator.of(context).pushReplacement(
              fadeRoute(BattleScreen(onExit: widget.onExit, monster: widget.monster ?? testMonsters[_monsterIndex])));
        } else {
          widget.onExit();
        }
      case _Phase.attack:
        break;
    }
  }

  int get _monsterIndex => switch (m) { WindroseKnight() => 1, GrumbleGust() => 2, _ => 0 };

  void _back() {
    switch (_phase) {
      case _Phase.interact:
      case _Phase.items:
        _phase = _Phase.menu;
      case _Phase.talk:
        _chars = currentLine.text.length.toDouble();
      case _Phase.menu:
        _flavorChars = _flavor.length.toDouble();
      default:
        break;
    }
  }

  int get _listLength => switch (_phase) {
        _Phase.pick => testMonsters.length,
        _Phase.interact => interactions.length,
        _Phase.items => items.length,
        _ => 0,
      };

  int get _columns => _phase == _Phase.pick ? 1 : 2;

  void _move(int dx, int dy) {
    if (_phase == _Phase.menu) {
      final b = (_button + dx + buttons.length) % buttons.length;
      if (b != _button) {
        _button = b;
        Sfx.blip();
      }
      return;
    }
    final n = _listLength;
    final s = _sel + (_columns == 1 ? dy : dx + dy * 2);
    if (n > 0 && s >= 0 && s < n && s != _sel) {
      _sel = s;
      Sfx.blip();
    }
  }

  // ---------------------------------------------------------------- STRIKE
  static Rect get strikeBar => Rect.fromLTWH(box.left + 24, box.center.dy - 14, box.width - 48, 28);

  double get strikeCursor {
    final u = ((_strikeStop ?? _t) - _strikeT0) / strikeTime;
    return strikeBar.left + u * strikeBar.width;
  }

  void _strike() {
    if (_strikeStop != null) return;
    _strikeStop = _t;
    final acc = 1 - ((strikeCursor - strikeBar.center.dx).abs() / (strikeBar.width / 2)).clamp(0.0, 1.0);
    final dmg = math.max(1, (acc * 10).round()) + counters * 5;
    counters = 0;
    lastDmg = dmg;
    hitT = _t + 0.35; // after the slash
    _later(0.35, () {
      m.hp = math.max(0, m.hp - dmg);
      m.hurt();
      _burst(enemyAt, 14, speed: 80);
      Sfx.blip();
    });
    _later(1.4, () => m.hp <= 0 ? _die() : _enemyTurn());
  }

  void _missStrike() {
    _strikeStop = _t;
    lastDmg = 0;
    hitT = _t;
    _later(1.0, _enemyTurn);
  }

  void _die() {
    final lines = m.dying;
    final last = lines.lastIndexWhere((l) => l.enemy);
    _talk(lines.sublist(0, last + 1), () {
      deathT = _t;
      _ending = _Ending.killed;
      GameState.addFallen();
      _phase = _Phase.done;
      _later(2.0, () => _talk([
            ...lines.sublist(last + 1),
            const BattleLine('Far below, a cold rain begins to fall.'),
            const BattleLine('You won. You feel a little colder.'),
          ], () => _phase = _Phase.done));
    });
  }

  // ---------------------------------------------------------------- ITEMS / spare / flee
  void _useItem(int i) {
    final name = items.removeAt(i);
    final before = hp;
    hp = math.min(maxHp, hp + (name == 'CANTEEN' ? 15 : 10));
    _talk([
      BattleLine(name == 'CANTEEN' ? 'You drink from the canteen.' : 'You eat the cloud bun. It tastes like nothing.'),
      BattleLine(hp == maxHp ? 'Your HP was maxed out.' : 'You recovered ${hp - before} HP!'),
    ], _enemyTurn);
  }

  void _spare() {
    if (!m.canSpare) {
      _talk([BattleLine('You offer ${m.title} a way out.'), const BattleLine('It isn\'t ready to stop yet.')], _enemyTurn);
      return;
    }
    _ending = _Ending.spared;
    spareT = _t;
    _talk(m.spared, () => _phase = _Phase.done);
  }

  void _flee() {
    if (_rng.nextDouble() < 0.5) {
      _ending = _Ending.fled;
      _talk(const [BattleLine('You slip away between the clouds...')], () => _phase = _Phase.done);
    } else {
      _talk(const [BattleLine('You try to slip away... but you are cut off!')], _enemyTurn);
    }
  }

  // ---------------------------------------------------------------- enemy turn
  void _enemyTurn() {
    if (m.canSpare) {
      _talk(const [BattleLine('...', enemy: true)], _toMenu);
      return;
    }
    _talk([BattleLine(m.taunt(_rng), enemy: true)], _startAttack);
  }

  void _startAttack() {
    final a = Arena(box);
    m.attack(a, _rng);
    arena = a;
    _trail.clear();
    _attackStart = _t + 0.4;
    _phase = _Phase.attack;
  }

  void _updateAttack(double dt) {
    final a = arena!;
    if (_t < _attackStart) return;
    final kb = HardwareKeyboard.instance;
    bool down(LogicalKeyboardKey k) => kb.isLogicalKeyPressed(k);

    var move = Offset.zero;
    if (down(LogicalKeyboardKey.keyA)) move += const Offset(-1, 0);
    if (down(LogicalKeyboardKey.keyD)) move += const Offset(1, 0);
    if (down(LogicalKeyboardKey.keyW)) move += const Offset(0, -1);
    if (down(LogicalKeyboardKey.keyS)) move += const Offset(0, 1);
    if (_moveFinger != null) {
      final d = _moveNow - _moveStart;
      if (d.distance > 4) move += d / d.distance;
    }

    var aim = Offset.zero;
    if (down(LogicalKeyboardKey.arrowLeft)) aim += const Offset(-1, 0);
    if (down(LogicalKeyboardKey.arrowRight)) aim += const Offset(1, 0);
    if (down(LogicalKeyboardKey.arrowUp)) aim += const Offset(0, -1);
    if (down(LogicalKeyboardKey.arrowDown)) aim += const Offset(0, 1);
    if (_guardFinger != null) {
      final drag = _guardNow - _guardStart;
      aim = drag.distance > 8 && !_guardIsMouse ? drag : _guardNow - a.soul;
    }
    final on = aim != Offset.zero;
    a.setGuard(on, on ? math.atan2(aim.dy, aim.dx) : a.guardAngle);

    final before = a.soul;
    final dmg = a.update(dt, move);
    if ((a.soul - before).distance > 0.3 && _t - _trailT > 0.07) {
      _trail.add((a.soul, _t));
      _trailT = _t;
    }
    _trail.removeWhere((p) => _t - p.$2 > 0.3);

    for (final (e, at) in a.events) {
      switch (e) {
        case ArenaEvent.perfect:
          _burst(at, 10, speed: 70);
          m.onPerfect();
          if (counters < maxCounters) {
            counters++;
            _popup('PERFECT', a.soul - const Offset(0, 34));
            _popup('+1 COUNTER', a.soul + const Offset(0, 30));
          } else {
            _popup('PERFECT', a.soul - const Offset(0, 34));
          }
          Sfx.blip();
        case ArenaEvent.block:
          _burst(at, 5, speed: 40, color: grey);
          _popup('BLOCK', a.soul - const Offset(0, 34), grey);
        case ArenaEvent.guardBreak:
          _popup('SCARF TIRED', a.soul - const Offset(0, 34), grey);
        case ArenaEvent.hit:
          break;
      }
    }
    a.events.clear();

    if (dmg > 0) _hurt(dmg);
    if (_phase == _Phase.attack && a.over) {
      arena = null;
      _toMenu();
    }
  }

  void _hurt(int dmg) {
    if (_ending != _Ending.none) return;
    hp = math.max(0, hp - dmg);
    _popup('-$dmg', arena!.soul - const Offset(0, 34), const Color(0xFFE8503A));
    Sfx.blip();
    if (hp > 0) return;
    _ending = _Ending.lost;
    _burst(arena!.soul, 24, speed: 60, color: const Color(0xFFE8503A));
    arena = null;
    _phase = _Phase.done;
    _later(1.4, () => _talk(const [
          BattleLine('The wind tears your scarf away...'),
          BattleLine('...but you catch it at the last moment. You hold on.'),
        ], () => _phase = _Phase.done));
  }

  // ---------------------------------------------------------------- frame
  void _tick(Duration d) {
    final now = d.inMicroseconds / 1e6;
    final dt = (now - _last).clamp(0.0, 0.05);
    _last = now;
    _t += dt;

    for (final tm in _timers.toList()) {
      if (_t >= tm.$1) {
        _timers.remove(tm);
        tm.$2();
      }
    }

    switch (_phase) {
      case _Phase.talk:
        final before = _chars.floor();
        _chars = math.min(currentLine.text.length.toDouble(), _chars + dt * 30);
        for (var i = before; i < _chars.floor(); i++) {
          if (i.isEven && currentLine.text[i] != ' ') Sfx.blip();
        }
      case _Phase.menu:
        final before = _flavorChars.floor();
        _flavorChars = math.min(_flavor.length.toDouble(), _flavorChars + dt * 30);
        for (var i = before; i < _flavorChars.floor(); i++) {
          if (i.isEven && _flavor[i] != ' ') Sfx.blip();
        }
      case _Phase.strike:
        if (_strikeStop == null && _t - _strikeT0 > strikeTime) _missStrike();
      case _Phase.attack:
        _updateAttack(dt);
      default:
        break;
    }

    for (final b in bits.toList()) {
      if (_t - b.t0 > 0.6) {
        bits.remove(b);
      } else {
        b.p += b.v * dt;
      }
    }
    popups.removeWhere((p) => _t - p.t0 > 0.9);
    _repaint.value++;
  }

  // ---------------------------------------------------------------- input
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (_img.isEmpty || e is KeyUpEvent) return KeyEventResult.handled;
    final k = e.logicalKey;
    if (_phase != _Phase.attack) {
      if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyA) _move(-1, 0);
      if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyD) _move(1, 0);
      if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.keyW) _move(0, -1);
      if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.keyS) _move(0, 1);
    }
    if (e is KeyRepeatEvent) return KeyEventResult.handled;
    if (k == LogicalKeyboardKey.escape) {
      widget.onExit();
    } else if (k == LogicalKeyboardKey.keyZ || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space) {
      _confirm();
    } else if (k == LogicalKeyboardKey.keyX || k == LogicalKeyboardKey.shiftLeft) {
      _back();
    }
    return KeyEventResult.handled;
  }

  void _onTouch(int id, TouchPhase phase, Offset p, bool mouse) {
    if (_img.isEmpty) return;
    if (phase == TouchPhase.down) {
      _guardIsMouse = mouse;
      if (_phase == _Phase.attack) {
        if (!mouse && p.dx < screenW / 2 && _moveFinger == null) {
          _moveFinger = id;
          _moveStart = _moveNow = p;
        } else if (_guardFinger == null) {
          _guardFinger = id;
          _guardStart = _guardNow = p;
        }
      } else {
        _tapOutsideArena(p);
      }
    } else if (phase == TouchPhase.move) {
      if (id == _moveFinger) _moveNow = p;
      if (id == _guardFinger) _guardNow = p;
    } else {
      if (id == _moveFinger) _moveFinger = null;
      if (id == _guardFinger) _guardFinger = null;
    }
  }

  void _tapOutsideArena(Offset p) {
    switch (_phase) {
      case _Phase.menu:
        for (var i = 0; i < buttons.length; i++) {
          if (_P.buttonRect(i).contains(p)) {
            _button = i;
            _pickButton();
            return;
          }
        }
        _flavorChars = _flavor.length.toDouble();
      case _Phase.pick:
      case _Phase.interact:
      case _Phase.items:
        for (var i = 0; i < _listLength; i++) {
          if (_P.listRect(i, _columns).inflate(3).contains(p)) {
            _sel = i;
            _confirm();
            return;
          }
        }
        if (!box.contains(p)) _back();
      default:
        _confirm();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: PixelStage(width: screenW, painter: _P(this, _repaint), onTouch: _onTouch),
      ),
    );
  }
}

class _P extends CustomPainter implements ArenaDraw {
  _P(this.s, Listenable repaint) : super(repaint: repaint);
  final _BattleScreenState s;
  final Paint _p = Paint()..isAntiAlias = false;

  static const black = Color(0xFF000000);
  static const frameGrey = Color(0xFFA0A0A0);
  static const red = Color(0xFFE8503A);

  static const box = _BattleScreenState.box;

  static Rect buttonRect(int i) => Rect.fromLTWH(80.0 + i * 110, 236, 100, 22);

  static Rect listRect(int i, int columns) => columns == 1
      ? Rect.fromLTWH(44, 60.0 + i * 18, 260, 9)
      : Rect.fromLTWH(i.isEven ? 44 : 180, 56.0 + (i ~/ 2) * 16, 130, 9);

  @override
  void rect(Canvas c, Rect r, Color col) {
    _p.color = col;
    c.drawRect(r, _p);
  }

  @override
  void line(Canvas c, Offset a, Offset b, Color col, double width) {
    final p = Paint()
      ..isAntiAlias = false
      ..color = col
      ..strokeWidth = width;
    c.drawLine(a, b, p);
  }

  void _frame(Canvas c, Rect r, Color col, [double w = 1]) {
    rect(c, Rect.fromLTWH(r.left, r.top, r.width, w), col);
    rect(c, Rect.fromLTWH(r.left, r.bottom - w, r.width, w), col);
    rect(c, Rect.fromLTWH(r.left, r.top, w, r.height), col);
    rect(c, Rect.fromLTWH(r.right - w, r.top, w, r.height), col);
  }

  void _text(Canvas c, String t, double x, double y, Color col,
      {bool center = false, bool right = false, double scale = 1, bool bold = false, double progress = double.infinity}) {
    _p.color = col;
    final w = PixelFont.width(t, scale);
    final x0 = (center ? x - w / 2 : (right ? x - w : x)).roundToDouble();
    PixelFont.draw(c, t, x0, y.roundToDouble(), _p, sx: scale, sy: scale, progress: progress);
    if (bold) PixelFont.draw(c, t, x0 + 1, y.roundToDouble(), _p, sx: scale, sy: scale, progress: progress);
  }

  @override
  void image(Canvas c, String name, Offset center, {double scale = 1, double opacity = 1, double angle = 0, bool flip = false, bool flash = false}) {
    final img = s._img[name];
    if (img == null || opacity <= 0) return;
    final p = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none
      ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));
    if (flash) p.colorFilter = const ColorFilter.mode(white, BlendMode.srcATop);
    final w = img.width * scale, h = img.height * scale;
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    c.save();
    c.translate(center.dx.roundToDouble(), center.dy.roundToDouble());
    if (angle != 0) c.rotate(angle);
    if (flip) c.scale(-1, 1);
    c.drawImageRect(img, src, Rect.fromLTWH((-w / 2).roundToDouble(), (-h / 2).roundToDouble(), w, h), p);
    c.restore();
  }

  static List<String> wrap(String text, int max) {
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

  void _typed(Canvas c, List<String> lines, double x, double y, Color col, double progress, {double lineH = 12, bool center = false}) {
    var left = progress;
    for (var i = 0; i < lines.length; i++) {
      _text(c, lines[i], x, y + i * lineH, col, progress: left, center: center);
      left -= lines[i].length + 1;
      if (left <= 0) break;
    }
  }

  @override
  void paint(Canvas c, Size size) {
    final t = s._t;
    rect(c, Offset.zero & size, black);

    if (s._phase == _Phase.pick) {
      _text(c, 'BATTLE PROTOTYPE', 240, 14, white, center: true, scale: 2);
      _frame(c, box, frameGrey, 2);
      const names = ['PRICKLE CUP      position', 'WINDROSE KNIGHT  direction', 'GRUMBLE GUST     timing'];
      for (var i = 0; i < names.length; i++) {
        _listItem(c, i, names[i], white, 1);
      }
      _text(c, 'WASD: move   ARROWS or MOUSE: hold the scarf out', 240, 224, grey, center: true);
      _text(c, 'Phone: left thumb moves, right thumb holds the scarf', 240, 238, grey, center: true);
      return;
    }

    _hud(c, t);
    _enemy(c, t);
    _frame(c, box, frameGrey, 2);
    _arenaContents(c, t);
    _bottom(c, t);

    for (final b in s.bits) {
      final a = (1 - (t - b.t0) / 0.6).clamp(0.0, 1.0);
      rect(c, Rect.fromLTWH(b.p.dx.roundToDouble(), b.p.dy.roundToDouble(), 2, 2), b.color.withValues(alpha: a));
    }
    for (final p in s.popups) {
      final k = (t - p.t0) / 0.9;
      _text(c, p.text, p.at.dx, p.at.dy - k * 8, p.color.withValues(alpha: (1.4 - k).clamp(0.0, 1.0)), center: true, bold: true);
    }

    if (s._phase == _Phase.talk && s.currentLine.enemy) _bubble(c);
  }

  void _hud(Canvas c, double t) {
    _text(c, 'HP ${s.hp}/${_BattleScreenState.maxHp}', 12, 10, white, bold: true);
    if (s.counters > 0) _text(c, 'COUNTER x${s.counters}', 12, 22, red, bold: true);
    _text(c, s.m.name, 468, 10, white, right: true, bold: true);
    final a = s.arena;
    if (a != null && a.title.isNotEmpty) {
      final long = a.title.length > 12;
      _text(c, a.title, 168, long ? 12 : 8, white, center: true, scale: long ? 1 : 2, bold: true);
    }
  }

  void _enemy(Canvas c, double t) {
    final img = s._img[s.m.sprite];
    if (img == null) return;
    var center = _BattleScreenState.enemyAt + Offset(0, math.sin(t * 2) * 1.5);
    var opacity = 1.0;
    final sinceHit = t - s.hitT;

    // lean in just before each telegraphed attack
    final a = s.arena;
    if (a != null) {
      for (final cue in a.cues) {
        final before = cue - a.t;
        if (before > 0 && before < 0.35) center += Offset(-4 * (1 - before / 0.35), 0);
      }
    }

    if (s.deathT >= 0) {
      final d = t - s.deathT;
      center += Offset(math.sin(t * 70) * (d < 0.8 ? 2 : 0), 0);
      opacity = (1 - (d - 0.8) / 0.9).clamp(0.0, 1.0);
      if (d > 0.8) {
        for (var i = 0; i < 60; i++) {
          final x = 340 + (i * 37.7 % 124);
          final y = 30 + ((i * 23.3 + d * 150) % 200);
          rect(c, Rect.fromLTWH(x.roundToDouble(), y.roundToDouble(), 1, 3), grey);
        }
      }
    } else if (s.spareT >= 0) {
      opacity = (1 - (t - s.spareT) * 0.25).clamp(0.4, 1.0);
    } else if (sinceHit >= 0 && sinceHit < 0.5) {
      center += Offset(math.sin(sinceHit * 60) * 4 * (1 - sinceHit * 2), 0);
    }
    image(c, s.m.sprite, center, opacity: opacity, flash: sinceHit >= 0 && sinceHit < 0.1);

    // the slash
    if (s._phase == _Phase.strike && s._strikeStop != null && s.lastDmg > 0) {
      final u = (t - s._strikeStop!) / 0.3;
      if (u >= 0 && u <= 1.2) {
        for (var i = 0; i < (math.min(u, 1) * 40).round(); i++) {
          rect(c, Rect.fromLTWH(372.0 + i * 1.5, 84.0 + i * 2, 2, 2), red);
        }
      }
    }

    if (sinceHit >= 0 && sinceHit < 1.0) {
      final top = center.dy - img.height / 2;
      if (s.lastDmg > 0) {
        _text(c, '${s.lastDmg}', 402, top - 26 + math.max(0.0, 8 - sinceHit * 40), white, center: true, scale: 2, bold: true);
        final bar = Rect.fromLTWH(367, top - 8, 70, 5);
        rect(c, bar, black);
        _frame(c, bar, white);
        rect(c, Rect.fromLTWH(bar.left + 1, bar.top + 1, (bar.width - 2) * s.m.hp / s.m.maxHp, bar.height - 2), white);
      } else {
        _text(c, 'MISS', 402, top - 20, grey, center: true, scale: 2);
      }
    }
  }

  void _arenaContents(Canvas c, double t) {
    switch (s._phase) {
      case _Phase.menu:
        _typed(c, wrap(s._flavor, 46), 30, 54, white, s._flavorChars);
      case _Phase.talk:
        if (!s.currentLine.enemy) _typed(c, wrap(s.currentLine.text, 46), 30, 54, white, s._chars);
      case _Phase.interact:
        final list = s.interactions;
        for (var i = 0; i < list.length; i++) {
          final spare = list[i] == 'SPARE';
          _listItem(c, i, list[i], spare && !s.m.canSpare ? grey : white, 2);
        }
      case _Phase.items:
        for (var i = 0; i < s.items.length; i++) {
          _listItem(c, i, s.items[i], white, 2);
        }
      case _Phase.strike:
        _strikeBar(c, t);
      case _Phase.attack:
        _arena(c, t);
      case _Phase.done:
        if (s._timers.isNotEmpty || (t * 2).floor().isOdd) break;
        if (s._ending == _Ending.lost) {
          _text(c, 'Press Z to try again', box.center.dx, box.center.dy - 4, white, center: true);
        } else if (s._ending != _Ending.none) {
          _text(c, 'Press Z to leave', box.center.dx, box.center.dy - 4, white, center: true);
        }
      case _Phase.pick:
        break;
    }
  }

  void _arena(Canvas c, double t) {
    final a = s.arena;
    if (a == null) return;
    c.save();
    c.clipRect(box.deflate(2));
    for (final h in a.hazards) {
      h.draw(c, this);
    }

    final flip = a.facing.dx < 0;
    for (final (p, at) in s._trail) {
      final k = 1 - (t - at) / 0.3;
      image(c, 'kid', p - const Offset(0, 6), opacity: 0.35 * k, flip: flip);
    }
    if (!a.hurtFlash || (t * 12).floor().isEven) image(c, 'kid', a.soul - const Offset(0, 6), flip: flip);

    // the scarf held out: a red crescent towards the aim
    if (a.guarding) {
      const n = 22;
      for (var i = 0; i <= n; i++) {
        final u = i / n * 2 - 1; // -1..1 across the arc
        final ang = a.guardAngle + u * Arena.guardHalfArc;
        final thick = 1 + 3 * (1 - u * u);
        for (var r = 0.0; r < thick; r += 1) {
          final p = a.soul + Offset(math.cos(ang), math.sin(ang)) * (16 + r);
          rect(c, Rect.fromLTWH(p.dx.roundToDouble(), p.dy.roundToDouble(), 2, 2), red);
        }
      }
    }
    // how tired the scarf is
    if (a.stamina < 1) {
      final bar = Rect.fromLTWH(a.soul.dx - 10, a.soul.dy + 18, 20, 3);
      rect(c, bar, dimGrey);
      rect(c, Rect.fromLTWH(bar.left, bar.top, bar.width * a.stamina, bar.height), a.tired ? grey : red);
    }
    c.restore();
  }

  void _bottom(Canvas c, double t) {
    if (s._phase == _Phase.attack) {
      final a = s.arena!;
      _text(c, 'ENEMY TURN', 168, 222, white, center: true, bold: true);
      _text(c, a.hint, 168, 238, grey, center: true);
      return;
    }
    final choosing = s._phase == _Phase.menu || s._phase == _Phase.interact || s._phase == _Phase.items;
    _text(c, 'YOUR TURN', 240, 220, choosing ? white : grey, center: true, bold: true);
    for (var i = 0; i < _BattleScreenState.buttons.length; i++) {
      final r = buttonRect(i);
      final on = i == s._button && choosing;
      _frame(c, r, on ? white : dimGrey, 2);
      final label = _BattleScreenState.buttons[i];
      if (on) {
        image(c, 'scarf_icon', Offset(r.left + 16, r.center.dy));
        _text(c, label, r.center.dx + 8, r.top + 8, white, center: true, bold: true);
      } else {
        _text(c, label, r.center.dx, r.top + 8, grey, center: true);
      }
    }
  }

  void _listItem(Canvas c, int i, String label, Color col, int columns) {
    final r = listRect(i, columns);
    _text(c, label, r.left, r.top + 1, col, bold: i == s._sel);
    if (i == s._sel) image(c, 'scarf_icon', Offset(r.left - 12, r.top + 4));
  }

  void _strikeBar(Canvas c, double t) {
    final bar = _BattleScreenState.strikeBar;
    final cx = bar.center.dx;
    rect(c, bar, black);
    for (final (w, col) in const [(0.6, dimGrey), (0.3, grey), (0.06, white)]) {
      final half = bar.width * w / 2;
      rect(c, Rect.fromLTRB(cx - half, bar.top + 1, cx + half, bar.bottom - 1), col);
    }
    _frame(c, bar, white);
    _text(c, 'Press Z when the line reaches the middle.', cx, bar.bottom + 12, grey, center: true);
    if (s.counters > 0) _text(c, 'COUNTER x${s.counters}: +${s.counters * 5} DAMAGE', cx, bar.top - 20, red, center: true, bold: true);
    final stopped = s._strikeStop != null;
    if (!stopped || (t * 10).floor().isEven) {
      final x = s.strikeCursor.clamp(bar.left, bar.right - 3).roundToDouble();
      rect(c, Rect.fromLTWH(x - 2, bar.top - 4, 6, bar.height + 8), black);
      rect(c, Rect.fromLTWH(x - 1, bar.top - 3, 4, bar.height + 6), red);
    }
  }

  void _bubble(Canvas c) {
    final img = s._img[s.m.sprite];
    final enemyTop = _BattleScreenState.enemyAt.dy - (img?.height ?? 80) / 2;
    final lines = wrap(s.currentLine.text, 22);
    final w = lines.fold<int>(0, (m, l) => math.max(m, l.length)) * 6 + 13.0;
    final h = lines.length * 11 + 10.0;
    final bottom = math.max(h + 30, enemyTop - 8);
    final left = (402 - w / 2).clamp(330.0, 476 - w);
    final r = Rect.fromLTWH(left, bottom - h, w, h);
    rect(c, r, black);
    rect(c, Rect.fromLTWH(r.left + 2, r.top, r.width - 4, 1), white);
    rect(c, Rect.fromLTWH(r.left + 2, r.bottom - 1, r.width - 4, 1), white);
    rect(c, Rect.fromLTWH(r.left, r.top + 2, 1, r.height - 4), white);
    rect(c, Rect.fromLTWH(r.right - 1, r.top + 2, 1, r.height - 4), white);
    for (final (x, y) in [(r.left + 1, r.top + 1), (r.right - 2, r.top + 1), (r.left + 1, r.bottom - 2), (r.right - 2, r.bottom - 2)]) {
      rect(c, Rect.fromLTWH(x, y, 1, 1), white);
    }
    // tail pointing down at the enemy
    final tx = 402.0.clamp(r.left + 8, r.right - 8).roundToDouble();
    rect(c, Rect.fromLTWH(tx - 3, r.bottom - 1, 7, 1), black);
    for (var i = 0; i < 4; i++) {
      rect(c, Rect.fromLTWH(tx - 3 + i, r.bottom - 1 + i, 1, 1), white);
      rect(c, Rect.fromLTWH(tx + 3 - i, r.bottom - 1 + i, 1, 1), white);
    }
    _typed(c, lines, r.left + 7, r.top + 6, white, s._chars, lineH: 11);
  }

  @override
  bool shouldRepaint(_P old) => false;
}
