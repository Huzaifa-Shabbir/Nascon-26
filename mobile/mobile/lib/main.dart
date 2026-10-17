import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadEnv();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const NasconApp(),
    ),
  );
}

class NasconApp extends StatelessWidget {
  const NasconApp({super.key});

  @override
  Widget build(BuildContext context) {
    const blue = Color(AppState.alphaBlue);
    const gold = Color(AppState.alphaGold);
    return MaterialApp(
      title: 'Alpha Sports',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: blue,
          primary: blue,
          secondary: gold,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            backgroundColor: blue,
          ),
        ),
        useMaterial3: true,
      ),
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Column(
      children: [
        const ConnectivityBanner(),
        Expanded(
          child: app.token == null ? const LoginScreen() : const HomeScreen(),
        ),
      ],
    );
  }
}

class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    late Color bg;
    late String label;
    late IconData icon;
    switch (app.netStatus) {
      case NetStatus.online:
        bg = Colors.green.shade700;
        label = app.pendingCount > 0 ? 'Online · ${app.pendingCount} pending' : 'Online';
        icon = Icons.cloud_done;
      case NetStatus.offline:
        bg = Colors.red.shade700;
        label = app.pendingCount > 0 ? 'Offline · ${app.pendingCount} queued' : 'Offline';
        icon = Icons.cloud_off;
      case NetStatus.syncing:
        bg = const Color(AppState.alphaGold);
        label = 'Syncing…';
        icon = Icons.sync;
    }
    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: () => app.refreshConnectivity(),
          child: SizedBox(
            height: 36,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
