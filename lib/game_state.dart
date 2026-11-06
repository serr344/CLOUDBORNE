import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small persistent game state.
///
/// Saving is best effort: if storage is blocked (for example a browser that refuses site data),
/// the game still runs and simply forgets between sessions.
class GameState {
  static String playerName = '';

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      playerName = prefs.getString('playerName') ?? '';
    } catch (e) {
      debugPrint('GameState.load failed: $e');
    }
  }

  static Future<void> setPlayerName(String name) async {
    playerName = name;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('playerName', name);
    } catch (e) {
      debugPrint('GameState.setPlayerName failed: $e');
    }
  }
}
