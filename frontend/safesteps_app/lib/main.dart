// lib/main.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'models/hex_zone_model.dart';
import 'services/hive_service.dart';

import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/confirm_screen.dart';
import 'screens/map_screen.dart';
import 'screens/report_screen.dart';
import 'screens/safety_navigator_page.dart';
import 'screens/prediction_screen.dart'; 

import 'services/auth_api.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(HexZoneAdapter()); // from hex_zone_model.g.dart
  }
  await HiveService.initHive();

  runApp(const SafeStepsApp());
}

// ========= auth-aware app =========
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
      title: 'SafeSteps',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      routes: <String, WidgetBuilder>{
        '/login': (ctx) => LoginScreen(onAuthenticated: _refreshAuth),
        '/signup': (ctx) => const SignUpScreen(),
        '/confirm': (ctx) => const ConfirmScreen(),
        '/map': (ctx) => const MapScreen(),
        '/report': (ctx) => const ReportScreen(),
        '/safety': (ctx) => const SafetyNavigatorPage(),
        '/predict': (ctx) => const PredictionScreen(),
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
          return isIn ? const _AuthedHome() : LoginScreen(onAuthenticated: _refreshAuth);
        },
      ),
    );
  }
}

class _AuthedHome extends StatefulWidget {
  const _AuthedHome({super.key});

  @override
  State<_AuthedHome> createState() => _AuthedHomeState();
}

class _AuthedHomeState extends State<_AuthedHome> {
  int _tab = 0;

  Future<void> _logout() async {
    await AuthApi.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const MapScreen(),
      const SafetyNavigatorPage(), // only visible after login
      const ReportScreen(),
      const PredictionScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeSteps'),
        actions: [
          IconButton(
            tooltip: 'Log out',
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
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.safety_check_outlined),
            selectedIcon: Icon(Icons.safety_check),
            label: 'Safety',
          ),
          NavigationDestination(
            icon: Icon(Icons.report_outlined),
            selectedIcon: Icon(Icons.report),
            label: 'Report',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Predict',
          ),
        ],
      ),
    );
  }
}
