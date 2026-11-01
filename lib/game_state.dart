import 'package:shared_preferences/shared_preferences.dart';

/// Small persistent game state. For now only the player's name.
class GameState {
  static String playerName = '';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    playerName = prefs.getString('playerName') ?? '';
  }

  static Future<void> setPlayerName(String name) async {
    playerName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('playerName', name);
  }
}
