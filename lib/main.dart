import 'package:flutter/material.dart';

import 'app_state.dart';
import 'core/vault_store.dart';
import 'ui/home_screen.dart';
import 'ui/lock_screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(await VaultStore.open());
  await state.init();
  runApp(MineAuthApp(state: state));
}

class MineAuthApp extends StatelessWidget {
  const MineAuthApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2F6FED),
            brightness: brightness,
          ),
        );
    return MaterialApp(
      title: 'Mine Auth',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) => switch (state.stage) {
          AppStage.needsSetup => SetupScreen(state: state),
          AppStage.locked => UnlockScreen(state: state),
          AppStage.unlocked => HomeScreen(state: state),
        },
      ),
    );
  }
}
