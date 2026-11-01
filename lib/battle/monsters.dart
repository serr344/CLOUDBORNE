import 'dart:math' as math;
import 'arena.dart';

/// A line of battle text. [enemy] lines go in the enemy's speech bubble, the rest under the arena.
class BattleLine {
  const BattleLine(this.text, {this.enemy = false});
  final String text;
  final bool enemy;
}

/// Everything that makes one enemy different. The battle screen and the arena are shared.
abstract class Monster {
  String get name;
  int get maxHp;
  late int hp = maxHp;

  /// 0..100. At 100 the enemy can be spared.
  double calm = 0;
  final Set<String> done = {};

  /// PERFECT blocks against this enemy so far.
  int perfects = 0;

  bool get canSpare => calm >= 100;

  /// Image in assets/images/battle, drawn 1:1 on the right.
  String get sprite;
  String get encounter;
  List<String> get acts;
  List<BattleLine> act(String a);
  String flavor(math.Random r);
  String taunt(math.Random r);

  /// Fills [a] with this turn's attack (and sets its title and hint).
  void attack(Arena a, math.Random r);
  List<BattleLine> get dying;
  List<BattleLine> get spared;

  /// Called when STRIKE lands a hit.
  void hurt() => calm = math.max(0, calm - 25);

  /// A PERFECT block impresses a little.
  void onPerfect() {
    perfects++;
    addCalm(4);
  }

  void addCalm(double v) => calm = (calm + v).clamp(0.0, 100.0);

  T pick<T>(math.Random r, List<T> list) => list[r.nextInt(list.length)];

  /// The name as it reads in sentences: "Prickle Cup".
  String get title => name.split(' ').map((w) => w[0] + w.substring(1).toLowerCase()).join(' ');
}

// ---------------------------------------------------------------- PRICKLE CUP
/// Teaches POSITION: thorns rise from marked ground. Touchy cactus in a cracked teacup.
class PrickleCup extends Monster {
  @override
  String get name => 'PRICKLE CUP';
  @override
  int get maxHp => 30;
  @override
  String get sprite => 'prickle_cup';
  @override
  String get encounter => 'Prickle Cup rattles on its saucer!';
  @override
  List<String> get acts => const ['CHECK', 'WATER IT', 'ADMIRE FLOWER', 'MIND THE CRACK', 'POKE'];

  @override
  List<BattleLine> act(String a) {
    switch (a) {
      case 'CHECK':
        return const [
          BattleLine('Prickle Cup - ATK 4 DEF 2'),
          BattleLine('A cactus that grew in a teacup. The cup is cracking. So is its patience.'),
        ];
      case 'WATER IT':
        if (!done.add(a)) return const [BattleLine('Its soil is still damp.')];
        addCalm(35);
        return const [
          BattleLine('You pour a little water from your canteen.'),
          BattleLine('Not too much! ...Okay. That was nice.', enemy: true),
        ];
      case 'ADMIRE FLOWER':
        if (!done.add(a)) return const [BattleLine('It is pretending not to blush.')];
        addCalm(35);
        return const [
          BattleLine('You tell it the flower on its head is lovely.'),
          BattleLine('It only blooms once a year. You noticed?', enemy: true),
        ];
      case 'MIND THE CRACK':
        if (done.contains(a)) return const [BattleLine('The crack is holding.')];
        if (calm < 30) {
          return const [
            BattleLine('You reach for the crack in its cup.'),
            BattleLine('Don\'t look at my cup!', enemy: true),
          ];
        }
        done.add(a);
        addCalm(35);
        return const [
          BattleLine('You wrap your scarf around the crack.'),
          BattleLine('It hurts less. Who taught you that?', enemy: true),
        ];
      default:
        addCalm(-20);
        return const [
          BattleLine('You poke it. Ouch.'),
          BattleLine('Why would you DO that?!', enemy: true),
        ];
    }
  }

  @override
  String flavor(math.Random r) {
    if (canSpare) return 'Prickle Cup has relaxed its thorns.';
    if (hp <= 10) return 'The cup is about to break.';
    return pick(r, const ['Prickle Cup bristles.', 'The cup creaks.', 'Smells like dry soil.']);
  }

  @override
  String taunt(math.Random r) => calm < 35
      ? pick(r, const ['Don\'t come any closer!', 'Every spot is my spot!', 'Mind your step!'])
      : pick(r, const ['Careful where you stand.', 'Thorns coming! Sorry!']);

  @override
  void attack(Arena a, math.Random r) {
    final angry = calm < 35;
    a.title = 'POSITION';
    a.length = 6.5;
    if (r.nextBool()) {
      a.hint = 'Move out before the thorns rise.';
      thornColumns(a, waves: angry ? 4 : 3, perWave: angry ? 3 : 2);
    } else {
      a.hint = 'Leave the marked ground. Block the needles.';
      thornPatches(a, count: angry ? 9 : 6);
      needles(a, count: angry ? 5 : 3, speed: 130);
    }
  }

  @override
  List<BattleLine> get dying => const [
        BattleLine('My cup...', enemy: true),
        BattleLine('Prickle Cup\'s cup shattered. The cactus wilted.'),
      ];

  @override
  List<BattleLine> get spared => const [
        BattleLine('You can go. Watch your step out there.', enemy: true),
        BattleLine('...And thanks for the water.', enemy: true),
        BattleLine('You won. Prickle Cup settles back into its cup.'),
      ];
}

// ---------------------------------------------------------------- WINDROSE KNIGHT
/// Teaches DIRECTION: spears from every side; later bouncing ones and charge + shockwave.
class WindroseKnight extends Monster {
  @override
  String get name => 'WINDROSE KNIGHT';
  @override
  int get maxHp => 45;
  @override
  String get sprite => 'windrose_knight';
  @override
  String get encounter => 'The Windrose Knight blocks the way up.';
  @override
  List<String> get acts => const ['CHECK', 'BOW', 'ASK ABOUT WAR', 'SHOW THE VINE', 'TURN AWAY'];

  @override
  List<BattleLine> act(String a) {
    switch (a) {
      case 'CHECK':
        return const [
          BattleLine('Windrose Knight - ATK 5 DEF 3'),
          BattleLine('She has guarded the way up since the sealing. She still keeps the old rules.'),
        ];
      case 'BOW':
        if (!done.add(a)) return const [BattleLine('You bow again. She nods, once.')];
        addCalm(30);
        return const [
          BattleLine('You bow. She lowers her spear for a moment.'),
          BattleLine('A Rootkin who knows manners. Strange.', enemy: true),
        ];
      case 'ASK ABOUT WAR':
        if (!done.contains('BOW')) {
          return const [BattleLine('I do not speak with those who have not bowed.', enemy: true)];
        }
        if (!done.add(a)) return const [BattleLine('She has said all she will say about it.')];
        addCalm(35);
        return const [
          BattleLine('Your people cut the winds. Mine sealed the sky.', enemy: true),
          BattleLine('Nobody remembers who started it. I still stand guard.', enemy: true),
        ];
      case 'SHOW THE VINE':
        if (!done.add(a)) return const [BattleLine('She is still staring at the vine.')];
        addCalm(35);
        return const [
          BattleLine('You point down at the vine you climbed.'),
          BattleLine('You climbed... all the way up? Alone?', enemy: true),
          BattleLine('...The old rules say nothing about that.', enemy: true),
        ];
      default:
        addCalm(-20);
        return const [
          BattleLine('You turn your back on her.'),
          BattleLine('Coward! Face the wind!', enemy: true),
        ];
    }
  }

  @override
  String flavor(math.Random r) {
    if (canSpare) return 'The Windrose Knight has lowered her spear.';
    if (hp <= 15) return 'Her windrose is barely turning.';
    return pick(r, const [
      'The Windrose Knight waits for your move.',
      'Her windrose spins slowly. It points at you.',
      'The wind here only blows one way.',
    ]);
  }

  @override
  String taunt(math.Random r) => calm < 35
      ? pick(r, const ['Turn back, Rootkin.', 'The wind decides.', 'En garde!'])
      : pick(r, const ['Show me how you move.', 'You dodge like a seed in the wind.']);

  @override
  void attack(Arena a, math.Random r) {
    final angry = calm < 35;
    a.title = 'DIRECTION';
    a.length = 6.5;
    switch (r.nextInt(3)) {
      case 0:
        a.hint = 'Face the next incoming strike.';
        spears(a, count: angry ? 8 : 6, speed: angry ? 230 : 200);
      case 1:
        a.hint = 'They bounce. Turn to where they come from last.';
        spears(a, count: angry ? 5 : 4, speed: 170, warn: 0.8, bounces: 1);
      default:
        a.title = 'POSITION + DIRECTION';
        a.hint = 'Step off the line. Then face the shockwave.';
        lanceShock(a, count: angry ? 3 : 2);
    }
  }

  @override
  List<BattleLine> get dying => const [
        BattleLine('The wind... has dropped...', enemy: true),
        BattleLine('The Windrose Knight fell. Her windrose stopped spinning.'),
      ];

  @override
  List<BattleLine> get spared => const [
        BattleLine('Go, then. The way up is open.', enemy: true),
        BattleLine('If anyone asks, you out-danced me.', enemy: true),
        BattleLine('You won. The Windrose Knight steps aside.'),
      ];
}

// ---------------------------------------------------------------- GRUMBLE GUST
/// Teaches TIMING: wind blades on a beat; raise the scarf just before each one lands.
class GrumbleGust extends Monster {
  @override
  String get name => 'GRUMBLE GUST';
  @override
  int get maxHp => 35;
  @override
  String get sprite => 'grumble_gust';
  @override
  String get encounter => 'Grumble Gust stomps in, huffing.';
  @override
  List<String> get acts => const ['CHECK', 'HUM ALONG', 'HOLD GROUND', 'ASK WHY', 'COMPLAIN'];

  @override
  List<BattleLine> act(String a) {
    switch (a) {
      case 'CHECK':
        return const [
          BattleLine('Grumble Gust - ATK 5 DEF 1'),
          BattleLine('Blows in rhythm when he\'s grumpy. Which is always.'),
        ];
      case 'HUM ALONG':
        if (!done.add(a)) return const [BattleLine('You hum. He taps a foot, then stops himself.')];
        addCalm(35);
        return const [
          BattleLine('You hum along to his huffing.'),
          BattleLine('Hmph. You\'re off-beat. ...A little.', enemy: true),
        ];
      case 'HOLD GROUND':
        if (done.contains(a)) return const [BattleLine('You hold your ground. He already knows you can.')];
        if (perfects == 0) {
          addCalm(5);
          return const [
            BattleLine('You plant your feet.'),
            BattleLine('Ha! Let\'s see you do that against a real gust!', enemy: true),
          ];
        }
        done.add(a);
        addCalm(35);
        return const [
          BattleLine('You plant your feet, like you did against his gusts.'),
          BattleLine('Nobody stands against my wind!', enemy: true),
          BattleLine('...Except you, I guess.', enemy: true),
        ];
      case 'ASK WHY':
        if (!done.add(a)) return const [BattleLine('He just huffs.')];
        addCalm(35);
        return const [
          BattleLine('You ask why he is so grumpy.'),
          BattleLine('The sky got sealed and the wind got stuck up here.', enemy: true),
          BattleLine('Round and round. Nowhere to blow.', enemy: true),
        ];
      default:
        addCalm(-20);
        return const [
          BattleLine('You complain about the wind.'),
          BattleLine('COMPLAIN?! I\'ll give you something to complain about!', enemy: true),
        ];
    }
  }

  @override
  String flavor(math.Random r) {
    if (canSpare) return 'Grumble Gust has run out of huff.';
    if (hp <= 12) return 'Grumble Gust is wheezing.';
    return pick(r, const ['Grumble Gust taps out a beat.', 'Grumble Gust puffs his cheeks.', 'It smells like a storm that never came.']);
  }

  @override
  String taunt(math.Random r) => calm < 35
      ? pick(r, const ['Hrrmph!', 'Brace yourself!', 'On the beat!'])
      : pick(r, const ['Ready? One, two...', 'Here comes a gentle one.']);

  @override
  void attack(Arena a, math.Random r) {
    final angry = calm < 35;
    a.title = 'TIMING';
    a.length = 6.5;
    if (r.nextBool()) {
      a.hint = 'Raise guard just before impact.';
      gustBeats(a, angry ? const [0.6, 1.5, 2.4, 2.8, 3.8, 4.7, 5.1] : const [0.8, 1.9, 3.0, 4.1, 5.2], speed: angry ? 200 : 170);
    } else {
      a.hint = 'He pushes you back. Keep your timing.';
      windPush(a, strength: -30, blow: 5, at: 0.2);
      gustBeats(a, angry ? const [1.0, 1.6, 2.6, 3.2, 4.2, 4.8] : const [1.0, 2.2, 3.4, 4.6], speed: 160);
    }
  }

  @override
  List<BattleLine> get dying => const [
        BattleLine('Phhhhh...', enemy: true),
        BattleLine('Grumble Gust blew himself out. The air goes still.'),
      ];

  @override
  List<BattleLine> get spared => const [
        BattleLine('Fine. I\'ll blow somewhere else.', enemy: true),
        BattleLine('Somewhere... up, maybe.', enemy: true),
        BattleLine('You won. Grumble Gust drifts off, grumbling softly.'),
      ];
}

/// Test enemies offered by the battle prototype, one per decision.
List<Monster Function()> get testMonsters => [PrickleCup.new, WindroseKnight.new, GrumbleGust.new];
