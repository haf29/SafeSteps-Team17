import 'package:flutter/material.dart';

import '../services/auth_api.dart';
import 'map_screen.dart';
import 'report_screen.dart';
import 'login_screen.dart';

/// Simple home with bottom tabs (Map / Report) and a Logout button.
/// No Provider dependency.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _loggingOut = false;

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    try {
      await AuthApi.logout();
    } catch (_) {
      // ignore network/auth errors on logout
    } finally {
      if (!mounted) return;
      setState(() => _loggingOut = false);
      // Clear stack and go to login
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LoginScreen(onAuthenticated: () {
          // After login, go back to Home
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        })),
        (r) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const MapScreen(),
      const ReportScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeSteps'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: _loggingOut ? null : _logout,
            icon: _loggingOut
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator())
                : const Icon(Icons.logout),
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
            icon: Icon(Icons.report_outlined),
            selectedIcon: Icon(Icons.report),
            label: 'Report',
          ),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.report),
              label: const Text('Report'),
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ReportScreen(),
              )),
            )
          : null,
    );
  }
}
