import 'dart:math' as math;
import 'dart:ui';

/// The dodge-and-guard arena shared by every enemy.
///
/// The player's tools never change:
/// - Position: move anywhere in the box. Ground hazards (hatched, with a warning sign) can't be
///   blocked; the only answer is to be somewhere else when they go off.
/// - Direction: hold the scarf out towards an angle. It blocks white things coming from that side.
/// - Timing: raising the scarf just before impact is a PERFECT block, which earns a counter for
///   your next turn. Holding the scarf up slows you down and tires it out, so you can't hide
///   behind it forever.
/// Enemies only differ in which hazards they put in the box (see the families at the bottom).

/// What hazards need in order to draw themselves.
abstract class ArenaDraw {
  void image(Canvas c, String name, Offset center, {double scale = 1, double opacity = 1, double angle = 0});
  void rect(Canvas c, Rect r, Color col);
  void line(Canvas c, Offset a, Offset b, Color col, double width);
}

const white = Color(0xFFFFFFFF);
const grey = Color(0xFF8A8A8A);
const dimGrey = Color(0xFF4A4A4A);

/// Something that happened this frame, for the screen to show.
enum ArenaEvent { perfect, block, guardBreak, hit }

class Arena {
  Arena(this.box) : soul = Offset(box.left + box.width * 0.35, box.center.dy);

  final Rect box;

  /// Seconds of attacking before the turn ends.
  double length = 6;

  /// Shown under the arena: which decision this attack asks for, and a hint.
  String title = '';
  String hint = '';

  Offset soul;
  Offset facing = const Offset(1, 0);
  final rng = math.Random();
  double t = 0;
  final List<Hazard> hazards = [];
  final List<(double, void Function())> _spawns = [];
  final List<(ArenaEvent, Offset)> events = [];

  /// Times the enemy telegraphs (winds up), so the screen can animate it.
  final List<double> cues = [];

  /// Push from wind this frame, in px/s.
  Offset wind = Offset.zero;

  static const speed = 95.0;
  static const guardSlow = 0.45;
  static const guardHalfArc = 1.1; // radians each side of the aim
  static const guardReach = 20.0;
  static const perfectWindow = 0.16;
  static const hitRadius = 6.0;
  static const mercyTime = 0.9;

  bool guarding = false;
  double guardAngle = 0;
  double guardT0 = -9;
  double stamina = 1;
  bool tired = false;
  double hurtT = -9;

  bool get hurtFlash => t - hurtT < mercyTime;
  bool get over => t >= length && _spawns.isEmpty;

  Rect get inner => box.deflate(10);

  Offset clampIn(Offset p) => Offset(p.dx.clamp(inner.left, inner.right), p.dy.clamp(inner.top, inner.bottom));

  Offset randomPoint([double margin = 0]) => Offset(
        inner.left + margin + rng.nextDouble() * (inner.width - 2 * margin),
        inner.top + margin + rng.nextDouble() * (inner.height - 2 * margin),
      );

  void at(double time, void Function() f) {
    _spawns.add((time, f));
    _spawns.sort((a, b) => a.$1.compareTo(b.$1));
  }

  void add(Hazard h) => hazards.add(h);

  /// Raises, aims or lowers the scarf.
  void setGuard(bool on, double angle) {
    guardAngle = angle;
    if (on && !guarding) {
      if (tired) return;
      guarding = true;
      guardT0 = t;
      stamina = math.max(0, stamina - 0.05);
    } else if (!on) {
      guarding = false;
    }
  }

  /// Drag input (touch); [d] is in virtual pixels.
  void moveBy(Offset d) {
    soul = clampIn(soul + d * (guarding ? guardSlow : 1));
    if (d.distance > 0.5) facing = d / d.distance;
  }

  bool faces(Offset from) {
    final d = from - soul;
    var diff = math.atan2(d.dy, d.dx) - guardAngle;
    while (diff > math.pi) {
      diff -= math.pi * 2;
    }
    while (diff < -math.pi) {
      diff += math.pi * 2;
    }
    return diff.abs() < guardHalfArc;
  }

  /// Advances the arena. Returns the damage taken this frame (0 if none).
  int update(double dt, Offset move) {
    t += dt;
    while (_spawns.isNotEmpty && _spawns.first.$1 <= t) {
      _spawns.removeAt(0).$2();
    }
    wind = Offset.zero;
    for (final h in hazards.toList()) {
      h.update(dt);
    }

    if (guarding) {
      stamina -= 0.4 * dt;
      if (stamina <= 0) {
        stamina = 0;
        guarding = false;
        tired = true;
        events.add((ArenaEvent.guardBreak, soul));
      }
    } else {
      stamina = math.min(1, stamina + 0.3 * dt);
      if (tired && stamina >= 0.4) tired = false;
    }

    if (move != Offset.zero) {
      facing = move / move.distance;
      soul += facing * speed * (guarding ? guardSlow : 1) * dt;
    }
    soul = clampIn(soul + wind * dt);
    hazards.removeWhere((h) => h.dead);

    var dmg = 0;
    for (final h in hazards) {
      final from = h.source(soul);
      if (from != null && guarding && faces(from) && h.touches(soul, guardReach)) {
        if (!h.blocked) {
          final perfect = t - guardT0 <= perfectWindow;
          events.add((perfect ? ArenaEvent.perfect : ArenaEvent.block, h.contact(soul)));
          if (!perfect) stamina = math.max(0, stamina - 0.15);
        }
        h.onBlocked();
        continue;
      }
      if (dmg == 0 && !hurtFlash && h.touches(soul, 0)) {
        hurtT = t;
        dmg = h.dmg;
        h.onHit();
        events.add((ArenaEvent.hit, soul));
      }
    }
    return dmg;
  }
}

// ---------------------------------------------------------------- building blocks

abstract class Hazard {
  Hazard(this.a, {this.dmg = 3}) : t0 = a.t;
  final Arena a;
  final double t0;
  final int dmg;
  bool dead = false;

  /// Set once the scarf has stopped it.
  bool blocked = false;

  double get age => a.t - t0;

  /// Where it comes from, if the scarf can block it; null for things you must move away from.
  Offset? source(Offset soul) => null;

  /// Whether it reaches the player, or reaches [extra] pixels further out (the scarf).
  bool touches(Offset soul, double extra) => false;

  /// Where a block shows its spark.
  Offset contact(Offset soul) => soul;

  void onBlocked() {
    blocked = true;
    dead = true;
  }

  void onHit() {}

  void update(double dt) {}
  void draw(Canvas c, ArenaDraw d);
}

/// A thrown thing. Blockable. Can bounce off the walls a number of times.
class Shot extends Hazard {
  Shot(super.a, this.p, this.v, this.sprite, {super.dmg, this.r = 3, this.scale = 1, this.bounces = 0, this.turn = true});
  Offset p, v;
  final String sprite;
  final double r, scale;
  int bounces;

  /// Rotate the sprite to its direction of travel.
  final bool turn;

  @override
  Offset? source(Offset soul) => p;

  @override
  bool touches(Offset soul, double extra) => (p - soul).distance < r + Arena.hitRadius + extra;

  @override
  Offset contact(Offset soul) => p;

  @override
  void onHit() => dead = true;

  @override
  void update(double dt) {
    p += v * dt;
    if (bounces > 0) {
      final b = a.box.deflate(3);
      var hit = false;
      if ((p.dx < b.left && v.dx < 0) || (p.dx > b.right && v.dx > 0)) {
        v = Offset(-v.dx, v.dy);
        hit = true;
      }
      if ((p.dy < b.top && v.dy < 0) || (p.dy > b.bottom && v.dy > 0)) {
        v = Offset(v.dx, -v.dy);
        hit = true;
      }
      if (hit) bounces--;
    }
    if (!a.box.inflate(60).contains(p)) dead = true;
  }

  @override
  void draw(Canvas c, ArenaDraw d) {
    final sp = v.distance;
    if (sp > 1) {
      final back = -v / sp;
      for (final k in const [10.0, 15.0, 20.0]) {
        final q = p + back * (k * scale);
        d.rect(c, Rect.fromLTWH(q.dx.roundToDouble(), q.dy.roundToDouble(), 2, 1), grey);
      }
    }
    d.image(c, sprite, p, scale: scale, angle: turn ? math.atan2(v.dy, v.dx) : 0);
  }
}

/// A dashed line showing a path, then calls [then].
class PathWarn extends Hazard {
  PathWarn(super.a, this.from, this.to, this.delay, this.then);
  final Offset from, to;
  final double delay;
  final void Function() then;

  @override
  void update(double dt) {
    if (age >= delay) {
      dead = true;
      then();
    }
  }

  @override
  void draw(Canvas c, ArenaDraw d) {
    final len = (to - from).distance;
    if (len < 1) return;
    final dir = (to - from) / len;
    final shown = len * math.min(1.0, age / (delay * 0.5));
    for (var s = 0.0; s < shown; s += 7) {
      final q = from + dir * s;
      d.rect(c, Rect.fromLTWH(q.dx.roundToDouble(), q.dy.roundToDouble(), 3, 1), grey);
    }
  }
}

/// Ground that warns (hatching and a sign), then sprouts thorns. Can't be blocked.
class Thorns extends Hazard {
  Thorns.rect(super.a, this.r, {super.dmg = 4, this.warn = 1.1, this.stay = 0.9})
      : center = null,
        radius = 0;
  Thorns.circle(super.a, Offset c, this.radius, {super.dmg = 4, this.warn = 1.0, this.stay = 0.7})
      : center = c,
        r = Rect.fromCircle(center: c, radius: radius);
  final Rect r;
  final Offset? center;
  final double radius, warn, stay;

  bool get live => age >= warn && age < warn + stay;

  bool _inside(Offset q) => center == null ? r.contains(q) : (q - center!).distance < radius;

  @override
  bool touches(Offset soul, double extra) => live && extra == 0 && _inside(soul);

  @override
  void update(double dt) {
    if (age > warn + stay) dead = true;
  }

  @override
  void draw(Canvas c, ArenaDraw d) {
    c.save();
    if (center == null) {
      c.clipRect(r);
    } else {
      c.clipPath(Path()..addOval(r));
    }
    if (!live) {
      // diagonal hatching, brighter as it gets closer
      final col = Color.lerp(dimGrey, grey, (age / warn).clamp(0.0, 1.0))!;
      for (var s = 0.0; s < r.width + r.height; s += 7) {
        d.line(c, Offset(r.left + s, r.top), Offset(r.left + s - r.height, r.bottom), col, 2);
      }
    } else {
      final rise = ((age - warn) / 0.12).clamp(0.0, 1.0);
      for (var y = r.top + 14; y < r.bottom + 14; y += 16) {
        for (var x = r.left + 4; x < r.right; x += 9) {
          final jitter = ((x * 7 + y * 3) % 5) - 2;
          d.image(c, 'thorn', Offset(x + jitter, y - 7 * rise), opacity: rise);
        }
      }
    }
    c.restore();
    if (!live && (age * 6).floor().isEven) {
      d.image(c, 'warning', Offset(r.center.dx, center == null ? r.top + 14 : r.center.dy));
    }
  }
}

/// A ring that grows out from a point. Blockable by facing its centre.
class Ring extends Hazard {
  Ring(super.a, this.c, {super.dmg = 4, this.speed = 110, this.maxR = 340});
  final Offset c;
  final double speed, maxR;
  bool _spent = false;

  double get radius => age * speed;

  @override
  Offset? source(Offset soul) => c;

  @override
  bool touches(Offset soul, double extra) {
    if (_spent) return false;
    final d = (soul - c).distance;
    return radius > d - Arena.hitRadius - extra - 2 && radius < d + Arena.hitRadius;
  }

  @override
  Offset contact(Offset soul) {
    final d = soul - c;
    return d.distance < 1 ? soul : c + d / d.distance * radius;
  }

  @override
  void onBlocked() {
    blocked = true;
    _spent = true;
  }

  @override
  void onHit() => _spent = true;

  @override
  void update(double dt) {
    if (radius > maxR) dead = true;
  }

  @override
  void draw(Canvas c, ArenaDraw d) {
    final n = (radius * 0.5).clamp(12, 120).round();
    for (var i = 0; i < n; i++) {
      final ang = i / n * math.pi * 2;
      final p = this.c + Offset(math.cos(ang), math.sin(ang)) * radius;
      d.rect(c, Rect.fromLTWH(p.dx.roundToDouble(), p.dy.roundToDouble(), 2, 2), white);
    }
  }
}

/// Rushes along a line after showing it. Can't be blocked.
class Charge extends Hazard {
  Charge(super.a, this.from, this.to, this.sprite, {super.dmg = 4, this.warn = 0.8, this.travel = 0.45, this.r = 8});
  final Offset from, to;
  final String sprite;
  final double warn, travel, r;

  Offset get pos => Offset.lerp(from, to, ((age - warn) / travel).clamp(0.0, 1.0))!;
  bool get live => age >= warn && age < warn + travel;

  @override
  bool touches(Offset soul, double extra) => live && extra == 0 && (soul - pos).distance < r + Arena.hitRadius;

  @override
  void update(double dt) {
    if (age > warn + travel + 0.05) dead = true;
  }

  @override
  void draw(Canvas c, ArenaDraw d) {
    if (!live) {
      final len = (to - from).distance;
      final dir = (to - from) / len;
      final col = (age * 10).floor().isEven ? grey : dimGrey;
      for (var s = 0.0; s < len; s += 6) {
        final q = from + dir * s;
        d.rect(c, Rect.fromLTWH(q.dx.roundToDouble() - 1, q.dy.roundToDouble() - 1, 3, 3), col);
      }
      return;
    }
    d.image(c, sprite, pos, angle: age * 20);
  }
}

/// Wind that pushes the player while it blows.
class Wind extends Hazard {
  Wind(super.a, this.push, {this.blow = 3});
  final Offset push;
  final double blow;

  @override
  void update(double dt) {
    a.wind += push;
    if (age > blow) dead = true;
  }

  @override
  void draw(Canvas c, ArenaDraw d) {
    final dir = push.dx >= 0 ? 1 : -1;
    final b = a.box;
    for (var i = 0; i < 24; i++) {
      final along = ((i * 53.0 + age * push.distance * 2.5) % (b.width + 20)) - 10;
      final y = b.top + (i * 37.0) % b.height;
      final x = dir > 0 ? b.left + along : b.right - along;
      d.rect(c, Rect.fromLTWH(x.roundToDouble(), y.roundToDouble(), 8, 1), dimGrey);
    }
  }
}

// ---------------------------------------------------------------- attack families

/// POSITION: columns of ground light up, then thorns rise. Always leaves safe columns.
void thornColumns(Arena a, {int waves = 3, int perWave = 2, double width = 44, double warn = 1.1}) {
  final b = a.inner;
  final slots = (b.width / width).floor();
  for (var i = 0; i < waves; i++) {
    a.at(0.2 + i * (a.length - 1.5) / waves, () {
      final picks = List.generate(slots, (k) => k)..shuffle(a.rng);
      for (final k in picks.take(math.min(perWave, slots - 1))) {
        a.add(Thorns.rect(a, Rect.fromLTWH(b.left + k * width, a.box.top + 2, width, a.box.height - 4), warn: warn));
      }
    });
  }
}

/// POSITION: patches of thorns, some right under you.
void thornPatches(Arena a, {int count = 8, double radius = 22, double onYou = 0.5, double over = 5}) {
  for (var i = 0; i < count; i++) {
    a.at(0.2 + i * over / count, () {
      final p = a.rng.nextDouble() < onYou ? a.soul : a.randomPoint(radius);
      a.add(Thorns.circle(a, p, radius));
    });
  }
}

/// DIRECTION: needles from the enemy's side, aimed at you.
void needles(Arena a, {int count = 6, double speed = 150, double over = 5}) {
  for (var i = 0; i < count; i++) {
    a.at(0.4 + i * over / count, () {
      final from = Offset(a.box.right + 4, a.box.top + 10 + a.rng.nextDouble() * (a.box.height - 20));
      final d = a.soul - from;
      a.add(Shot(a, from, d / d.distance * speed, 'needle', r: 3));
    });
  }
}

/// TIMING: wind blades on a beat, each announced by the enemy winding up.
void gustBeats(Arena a, List<double> beats, {double speed = 170}) {
  for (final at in beats) {
    a.cues.add(at);
    a.at(at, () {
      final from = Offset(a.box.right + 6, a.soul.dy);
      a.add(Shot(a, from, Offset(-speed, 0), 'gust', r: 9, scale: 3, turn: false, dmg: 4));
    });
  }
}

/// DIRECTION: spears from every side, each with its path shown first. Some bounce.
void spears(Arena a, {int count = 7, double speed = 210, double warn = 0.7, double over = 5.2, int bounces = 0}) {
  for (var i = 0; i < count; i++) {
    final at = 0.3 + i * over / count;
    a.cues.add(at);
    a.at(at, () {
      final target = a.soul;
      final ang = a.rng.nextDouble() * math.pi * 2;
      final dir = Offset(math.cos(ang), math.sin(ang));
      // start where that direction leaves the box
      var from = target;
      while (a.box.deflate(2).contains(from)) {
        from -= dir * 4;
      }
      a.add(PathWarn(a, from, target, warn, () => a.add(Shot(a, from, dir * speed, 'spear', r: 3, bounces: bounces))));
    });
  }
}

/// A charge along a shown line (move off it), then a shockwave where it lands (face it, block it).
void lanceShock(Arena a, {int count = 2, double over = 5}) {
  for (var i = 0; i < count; i++) {
    a.at(0.2 + i * over / count, () {
      final hit = a.randomPoint(30);
      final ang = a.rng.nextDouble() * math.pi * 2;
      final dir = Offset(math.cos(ang), math.sin(ang));
      final charge = Charge(a, hit - dir * 260, hit, 'windrose_spin');
      a.add(charge);
      a.at(a.t + charge.warn + charge.travel, () => a.add(Ring(a, hit)));
    });
  }
}

/// Wind pushes you sideways for a while.
void windPush(Arena a, {double strength = 40, double blow = 3, double at = 0.5}) {
  a.at(at, () => a.add(Wind(a, Offset(strength, 0), blow: blow)));
}
