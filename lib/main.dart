import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/cloud_sync.dart';
import 'core/credential_store.dart';
import 'core/database.dart';
import 'core/fitness_store.dart';
import 'features/dashboard/main_screen.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  /// Overrides the on-device database, for tests.
  final AppDatabase? database;

  /// Overrides where the cloud session is kept, for tests.
  final CredentialStore? credentials;
  const MyApp({super.key, this.database, this.credentials});
  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => FitnessStore(database)..load()),
      ChangeNotifierProvider(
        create: (context) =>
            CloudSync(context.read<FitnessStore>(), credentials: credentials)
              ..restore(),
      ),
    ],
    child: _SyncOnResume(
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
    ),
  );
}

/// Syncs when the app returns to the foreground.
class _SyncOnResume extends StatefulWidget {
  final Widget child;
  const _SyncOnResume({required this.child});
  @override
  State<_SyncOnResume> createState() => _SyncOnResumeState();
}

class _SyncOnResumeState extends State<_SyncOnResume>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) context.read<CloudSync>().resumed();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
