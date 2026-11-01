import 'dart:async';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Background music: one track at a time, looping, with fades.
/// The intro uses theme_lullaby.wav.
class Music {
  static final AudioPlayer _player = AudioPlayer();
  static Timer? _fade;
  static String? _current;

  static Future<void> play(String asset, {double volume = 0.55}) async {
    if (_current == asset) return;
    _fade?.cancel();
    _current = asset;
    await _player.stop();
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(volume);
    await _player.play(AssetSource(asset));
  }

  static void fadeOut([Duration over = const Duration(milliseconds: 1500)]) {
    if (_current == null) return;
    _fade?.cancel();
    const steps = 20;
    var step = 0;
    final start = _player.volume;
    _fade = Timer.periodic(over ~/ steps, (t) {
      step++;
      _player.setVolume(start * (1 - step / steps));
      if (step >= steps) {
        t.cancel();
        _player.stop();
        _current = null;
      }
    });
  }
}

/// Short sound effects. The text blip is the "voice" of typed dialogue: a soft wooden
/// marimba "tok" in three slightly different pitches.
///
/// Six preloaded players (two per pitch) are used round-robin, which works reliably in browsers.
/// [init] is safe to call many times; call it from a user gesture so the browser allows audio.
class Sfx {
  static const _count = 6;
  static final List<AudioPlayer> _players = [];
  static final math.Random _rng = math.Random();
  static Future<void>? _ready;

  static Future<void> init() => _ready ??= _load().catchError((Object e) {
        debugPrint('Sfx.init failed: $e');
        _ready = null; // try again on the next call
      });

  static Future<void> _load() async {
    final players = <AudioPlayer>[];
    for (var i = 0; i < _count; i++) {
      final p = AudioPlayer();
      await p.setReleaseMode(ReleaseMode.stop); // keep the source loaded after it finishes
      await p.setVolume(0.5);
      await p.setSource(AssetSource('audio/text_wood_${i % 3}.wav'));
      players.add(p);
    }
    _players.addAll(players);
  }

  static void blip() {
    if (_players.isEmpty) {
      init();
      return;
    }
    // a random free-ish player: start from a random one so the three pitches mix
    final p = _players[_rng.nextInt(_players.length)];
    p.seek(Duration.zero).then((_) => p.resume()).catchError((Object e) => debugPrint('Sfx.blip failed: $e'));
  }
}
