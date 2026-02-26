import 'package:flutter/material.dart';

import '../core/i18n/app_strings.dart';
import '../features/focus/focus_page.dart';
import '../features/inbox/inbox_page.dart';
import '../features/library/library_page.dart';
import 'router.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialEntry = PrimaryEntry.inbox});

  final PrimaryEntry initialEntry;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late PrimaryEntry _currentEntry;

  @override
  void initState() {
    super.initState();
    _currentEntry = widget.initialEntry;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(primaryEntryTitle(_currentEntry))),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              const ListTile(
                title: Text(AppStrings.navTitle),
                subtitle: Text(AppStrings.navSubtitle),
              ),
              _drawerItem(
                context: context,
                entry: PrimaryEntry.inbox,
                icon: Icons.inbox_outlined,
                label: AppStrings.inbox,
              ),
              _drawerItem(
                context: context,
                entry: PrimaryEntry.library,
                icon: Icons.library_books_outlined,
                label: AppStrings.library,
              ),
              _drawerItem(
                context: context,
                entry: PrimaryEntry.focus,
                icon: Icons.timer_outlined,
                label: AppStrings.focus,
              ),
            ],
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: switch (_currentEntry) {
          PrimaryEntry.inbox => const InboxPage(),
          PrimaryEntry.library => const LibraryPage(),
          PrimaryEntry.focus => const FocusPage(),
        },
      ),
    );
  }

  Widget _drawerItem({
    required BuildContext context,
    required PrimaryEntry entry,
    required IconData icon,
    required String label,
  }) {
    return ListTile(
      leading: Icon(icon),
      selected: _currentEntry == entry,
      title: Text(label),
      onTap: () {
        setState(() {
          _currentEntry = entry;
        });
        Navigator.of(context).pop();
      },
    );
  }
}
