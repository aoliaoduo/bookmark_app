import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/backup/backup_providers.dart';
import '../core/db/app_database.dart';
import '../core/db/db_provider.dart';
import '../core/i18n/app_strings.dart';
import '../core/notify/notify_providers.dart';
import '../features/focus/focus_page.dart';
import '../features/inbox/inbox_page.dart';
import '../features/library/library_page.dart';
import '../features/search/search_page.dart';
import '../features/settings/sync_page.dart';
import 'router.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, this.initialEntry = PrimaryEntry.inbox});

  final PrimaryEntry initialEntry;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late PrimaryEntry _currentEntry;
  bool _backupReminderChecked = false;
  bool _todoReminderStarted = false;

  @override
  void initState() {
    super.initState();
    _currentEntry = widget.initialEntry;
  }

  @override
  Widget build(BuildContext context) {
    if (!_backupReminderChecked) {
      _backupReminderChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          return;
        }
        final dbAsync = ref.read(appDatabaseProvider);
        if (dbAsync case AsyncData<AppDatabase>()) {
          await ref.read(backupReminderServiceProvider).checkAndPrompt(context);
        }
      });
    }
    if (!_todoReminderStarted) {
      _todoReminderStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          return;
        }
        final dbAsync = ref.read(appDatabaseProvider);
        if (dbAsync case AsyncData<AppDatabase>()) {
          await ref.read(todoReminderRuntimeProvider).start();
        }
      });
    }

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
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text(AppStrings.search),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const SearchPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text(AppStrings.syncAndBackup),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const SyncPage()),
                  );
                },
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
