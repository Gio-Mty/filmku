import 'package:flutter/material.dart';

import '../theme.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'my_list_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment(0, 0.2),
          colors: [AppColors.bgTop, AppColors.bg],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: const [HomeScreen(), MyListScreen(), HistoryScreen()],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Beranda'),
            NavigationDestination(
                icon: Icon(Icons.bookmark_border_rounded),
                selectedIcon: Icon(Icons.bookmark_rounded),
                label: 'Daftarku'),
            NavigationDestination(
                icon: Icon(Icons.history_rounded),
                selectedIcon: Icon(Icons.history_rounded),
                label: 'Riwayat'),
          ],
        ),
      ),
    );
  }
}
