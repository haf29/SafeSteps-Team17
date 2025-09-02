import 'package:flutter/material.dart';

class PredictionScreen extends StatelessWidget {
  const PredictionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          'ML Prediction Page',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    );
  }
}
