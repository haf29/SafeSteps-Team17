import 'package:flutter/material.dart';
import 'screens/map_screen.dart';
import 'screens/report_screen.dart'; 

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeSteps Map',
      theme: ThemeData(primarySwatch: Colors.blue),
      debugShowCheckedModeBanner: false,
      home: const MapScreen(),
      routes: {
        '/report': (context) => const ReportScreen(),
      },
    );
  }
}