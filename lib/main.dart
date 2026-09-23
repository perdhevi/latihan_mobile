import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/fitness_store.dart';
import 'features/dashboard/main_screen.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => FitnessStore()..load(),
    child: MaterialApp(
      title: 'FitTrack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF121310),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD4FF45),
          brightness: Brightness.dark,
          primary: const Color(0xFFD4FF45),
          surface: const Color(0xFF1E201A),
        ),
        cardTheme: const CardThemeData(
          margin: EdgeInsets.symmetric(vertical: 6),
          elevation: 0,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          ),
        ),
      ),
      home: const MainScreen(),
    ),
  );
}
