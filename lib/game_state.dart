import 'package:shared_preferences/shared_preferences.dart';

/// Small persistent game state.
class GameState {
  static String playerName = '';

  /// How many enemies were blown off a cloud edge (they turn into rain). The true ending needs 0.
  static int fallen = 0;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    playerName = prefs.getString('playerName') ?? '';
    fallen = prefs.getInt('fallen') ?? 0;
  }

  static Future<void> setPlayerName(String name) async {
    playerName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('playerName', name);
  }

  static Future<void> addFallen() async {
    fallen++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('fallen', fallen);
  }
}
