/// ============================================================================
/// Daemon - V2X Roadside Assistance Simulation
/// ============================================================================
/// A Flutter application that simulates Vehicle-to-Everything (V2X) communication
/// between cars and Roadside Units (RSUs) using CSMA/CA-like MAC protocol.
///
/// Supports two modes:
/// - Classic mode: Standard CSMA/CA with RTS/CTS handshake
/// - MDP mode: Reinforcement Learning agents (Q-Learning) for adaptive behavior
/// ============================================================================

import 'package:flutter/material.dart';
import 'package:daemon/presentation/home.dart';

void main() {
  runApp(const MyApp());
}

/// Root widget that configures the app theme and launches the home page.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 221, 93, 223),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color.fromARGB(255, 250, 250, 250),
        ),
        scaffoldBackgroundColor: const Color.fromARGB(255, 255, 255, 255),
      ),
      home: const MyHomePage(title: 'Roadside Assistance'),
    );
  }
}
