import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/fitness_store.dart';
import '../ideas/ideas_screen.dart';
import '../plans/plans_screen.dart';
import '../profile/profile_screen.dart';
import 'dashboard_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int selectedIndex = 0;
  final visited = <int>{0};

  void select(int index) {
    setState(() {
      selectedIndex = index;
      visited.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FitnessStore>();
    final enabled = !store.loading && store.error == null;
    return PopScope(
      canPop: selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selectedIndex != 0) select(0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: selectedIndex,
          children: [
            const DashboardScreen(),
            if (visited.contains(1))
              const HistoryScreen()
            else
              const SizedBox.shrink(),
            // Dispose video players when leaving Ideas so audio cannot continue
            // playing behind another tab. Other tabs retain their local state.
            if (selectedIndex == 2)
              const IdeasScreen()
            else
              const SizedBox.shrink(),
            if (visited.contains(3))
              const PlansScreen()
            else
              const SizedBox.shrink(),
            if (visited.contains(4))
              const ProfileScreen()
            else
              const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: select,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              enabled: enabled,
              icon: const Icon(Icons.history_outlined),
              selectedIcon: const Icon(Icons.history),
              label: 'Sessions',
              tooltip: 'Previous sessions',
            ),
            NavigationDestination(
              enabled: enabled,
              icon: const Icon(Icons.play_circle_outline),
              selectedIcon: const Icon(Icons.play_circle),
              label: 'Ideas',
              tooltip: 'Exercise ideas',
            ),
            NavigationDestination(
              enabled: enabled,
              icon: const Icon(Icons.calendar_month_outlined),
              selectedIcon: const Icon(Icons.calendar_month),
              label: 'Plan',
              tooltip: 'Coach / Plan',
            ),
            NavigationDestination(
              enabled: enabled,
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: 'Profile',
              tooltip: 'My profile',
            ),
          ],
        ),
      ),
    );
  }
}
