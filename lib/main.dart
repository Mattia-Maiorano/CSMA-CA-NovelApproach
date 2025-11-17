import 'package:flutter/material.dart';
import 'package:daemon/pages/home.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color.fromARGB(255, 221, 93, 223)),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color.fromARGB(255, 221, 93, 223),
        ),
        scaffoldBackgroundColor: const Color.fromARGB(255, 221, 93, 223)
      ),
      home: const MyHomePage(title: 'Daemon'),
    );
  }
}

