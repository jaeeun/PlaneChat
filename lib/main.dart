import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/name_screen.dart';
import 'screens/lobby_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const PlaneChat(),
    ),
  );
}

class PlaneChat extends StatelessWidget {
  const PlaneChat({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlaneChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: Consumer<AppState>(
        builder: (context, state, _) {
          if (state.currentUserName == null) {
            return const NameScreen();
          }
          return const LobbyScreen();
        },
      ),
    );
  }
}
