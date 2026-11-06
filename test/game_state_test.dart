import 'package:cloudborne/game_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the player name survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    await GameState.setPlayerName('SPROUT');
    GameState.playerName = '';
    await GameState.load();
    expect(GameState.playerName, 'SPROUT');
  });
}
