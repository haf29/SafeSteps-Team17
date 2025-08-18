// lib/main.dart
import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/confirm_screen.dart';
import 'screens/map_screen.dart';
import 'screens/report_screen.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/hex_zone_model.dart';

// ADD THIS IMPORT so references to AuthApi compile:
import 'services/auth_api.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(HexZoneAdapter());
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeSteps',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      initialRoute: '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignUpScreen(),
        '/confirm': (_) => const ConfirmScreen(),
        '/map': (_) => const MapScreen(),
        '/report': (_) => const ReportScreen(),
      },
    );
  }
}

class SafeStepsApp extends StatefulWidget {
  const SafeStepsApp({super.key});
  @override
  State<SafeStepsApp> createState() => _SafeStepsAppState();
}

class _SafeStepsAppState extends State<SafeStepsApp> {
  Future<bool>? _isLoggedIn;

  @override
  void initState() {
    super.initState();
    _isLoggedIn = AuthApi.isLoggedIn();
  }

  void _refreshAuth() {
    setState(() {
      _isLoggedIn = AuthApi.isLoggedIn();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "SafeSteps",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      routes: {
        "/login": (ctx) => LoginScreen(onAuthenticated: _refreshAuth),
        "/signup": (ctx) => const SignUpScreen(),
        "/confirm": (ctx) => const ConfirmScreen(),
        "/map": (ctx) => const MapScreen(),
        "/report": (ctx) => const ReportScreen(),
      },
      home: FutureBuilder<bool>(
        future: _isLoggedIn,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final isIn = snap.data == true;
          return isIn
              ? const _AuthedHome()
              : LoginScreen(onAuthenticated: _refreshAuth);
        },
      ),
    );
  }
}

class _AuthedHome extends StatefulWidget {
  const _AuthedHome();

  @override
  State<_AuthedHome> createState() => _AuthedHomeState();
}

class _AuthedHomeState extends State<_AuthedHome> {
  int _tab = 0;

  Future<void> _logout() async {
    await AuthApi.logout();
    if (!mounted) return;
    // Clear stack and go to login
    Navigator.of(context).pushNamedAndRemoveUntil("/login", (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const MapScreen(),
      const ReportScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text("SafeSteps"),
        actions: [
          IconButton(
            tooltip: "Log out",
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: "Map"),
          NavigationDestination(
              icon: Icon(Icons.report_outlined),
              selectedIcon: Icon(Icons.report),
              label: "Report"),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.report),
              label: const Text("Report"),
              onPressed: () => Navigator.of(context).pushNamed("/report"),
            )
          : null,
    );
  }
}
