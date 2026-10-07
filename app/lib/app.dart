import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/schedule/schedule_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/today/today_screen.dart';

/// Which tab is showing. Screens change it to send you somewhere (for example "set up the server").
class SelectedTab extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final selectedTabProvider = NotifierProvider<SelectedTab, int>(SelectedTab.new);

const tabToday = 0;
const tabSchedule = 1;
const tabSettings = 2;

// UC Santa Cruz blue and gold.
const _ucscBlue = Color(0xFF003C6C);

class UcscRouterApp extends StatelessWidget {
  const UcscRouterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UCSC Router',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: _ucscBlue), useMaterial3: true),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _ucscBlue, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(selectedTabProvider);
    const screens = [TodayScreen(), ScheduleScreen(), SettingsScreen()];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: index, children: screens)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: ref.read(selectedTabProvider.notifier).select,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Schedule'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
