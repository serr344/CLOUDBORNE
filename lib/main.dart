import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'game_state.dart';
import 'screens/title_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GameState.load();
  SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  runApp(const CloudborneApp());
}

class CloudborneApp extends StatelessWidget {
  const CloudborneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CLOUDBORNE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const TitleScreen(),
    );
  }
}
