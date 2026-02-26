import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai/ai_provider_providers.dart';
import '../core/backup/backup_providers.dart';
import '../core/backup/backup_settings_repository.dart';
import '../core/db/app_database.dart';
import '../core/db/db_provider.dart';
import '../core/i18n/app_strings.dart';
import '../core/notify/notify_providers.dart';
import '../core/ux/shortcut_bus.dart';
import '../features/focus/focus_page.dart';
import '../features/inbox/inbox_page.dart';
import '../features/library/library_page.dart';
import '../features/search/search_page.dart';
import '../features/settings/maintenance_page.dart';
import '../features/settings/settings_page.dart';
import '../features/tags/tags_page.dart';
import 'router.dart';

class DrawerStatusSnapshot {
  const DrawerStatusSnapshot({
    required this.aiReady,
    required this.aiError,
    required this.syncLastAt,
    required this.syncError,
    required this.backupLastAt,
    required this.backupNextPromptAt,
    required this.backupError,
    required this.notifyPending,
  });

  final bool aiReady;
  final String aiError;
  final int? syncLastAt;
  final String syncError;
  final int? backupLastAt;
  final DateTime backupNextPromptAt;
  final String backupError;
  final int notifyPending;
}

final FutureProvider<DrawerStatusSnapshot> drawerStatusProvider =
    FutureProvider<DrawerStatusSnapshot>((Ref ref) async {
      final AppDatabase database = ref.watch(appDatabaseProvider).requireValue;
      final aiConfig = await ref.read(aiProviderRepositoryProvider).load();
      final String aiError = await _loadKv(database, 'ai_last_error');

      final List<Map<String, Object?>> syncRows = await database.db.query(
        'sync_state',
        where: 'id = ?',
        whereArgs: const <Object?>['singleton'],
        limit: 1,
      );
      final int? syncLastAt = syncRows.isEmpty
          ? null
          : (syncRows.first['last_sync_finished_at'] as num?)?.toInt();
      final String syncError = syncRows.isEmpty
          ? ''
          : ((syncRows.first['last_error'] as String?) ?? '');

      final BackupSettings backupSettings = await ref
          .read(backupSettingsRepositoryProvider)
          .loadSettings();
      final String backupLastRaw = await _loadKv(
        database,
        'backup_last_success_at',
      );
      final int? backupLastAt = int.tryParse(backupLastRaw);
      final String backupError = await _loadKv(database, 'backup_last_error');
      final DateTime backupNextPromptAt = _nextBackupPrompt(
        now: DateTime.now(),
        hour: backupSettings.reminderHour,
        minute: backupSettings.reminderMinute,
      );

      final List<Map<String, Object?>> queueRows = await database.db.rawQuery(
        '''
        SELECT COUNT(*) AS c
        FROM notification_jobs
        WHERE status = ?
        ''',
        <Object?>['queued'],
      );
      final int notifyPending = queueRows.isEmpty
          ? 0
          : ((queueRows.first['c'] as num?)?.toInt() ?? 0);

      return DrawerStatusSnapshot(
        aiReady: aiConfig.isReady,
        aiError: aiError,
        syncLastAt: syncLastAt,
        syncError: syncError,
        backupLastAt: backupLastAt,
        backupNextPromptAt: backupNextPromptAt,
        backupError: backupError,
        notifyPending: notifyPending,
      );
    });

Future<String> _loadKv(AppDatabase database, String key) async {
  final List<Map<String, Object?>> rows = await database.db.query(
    'kv',
    columns: <String>['value'],
    where: 'key = ?',
    whereArgs: <Object?>[key],
    limit: 1,
  );
  if (rows.isEmpty) {
    return '';
  }
  return (rows.first['value'] as String?) ?? '';
}

DateTime _nextBackupPrompt({
  required DateTime now,
  required int hour,
  required int minute,
}) {
  DateTime next = DateTime(now.year, now.month, now.day, hour, minute);
  if (!next.isAfter(now)) {
    next = next.add(const Duration(days: 1));
  }
  return next;
}

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

    final AsyncValue<DrawerStatusSnapshot> statusAsync = ref.watch(
      drawerStatusProvider,
    );
    final Widget scaffold = Scaffold(
      appBar: AppBar(title: Text(primaryEntryTitle(_currentEntry))),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              const ListTile(
                title: Text(AppStrings.navTitle),
                subtitle: Text(AppStrings.navSubtitle),
              ),
              _buildStatusSection(statusAsync),
              const Divider(height: 12),
              _sectionLabel(AppStrings.navMainSection),
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
              const Divider(height: 12),
              _sectionLabel(AppStrings.navToolsSection),
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
                leading: const Icon(Icons.sell_outlined),
                title: const Text(AppStrings.tags),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const TagsPage()),
                  );
                },
              ),
              const Divider(height: 12),
              _sectionLabel(AppStrings.navSystemSection),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text(AppStrings.settings),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsPage(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.build_outlined),
                title: const Text(AppStrings.maintenance),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MaintenancePage(),
                    ),
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

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _FocusInboxIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _OpenSearchIntent(),
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _FocusInboxIntent: CallbackAction<_FocusInboxIntent>(
            onInvoke: (_FocusInboxIntent intent) {
              setState(() {
                _currentEntry = PrimaryEntry.inbox;
              });
              requestInboxFocus(ref);
              return null;
            },
          ),
          _OpenSearchIntent: CallbackAction<_OpenSearchIntent>(
            onInvoke: (_OpenSearchIntent intent) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SearchPage()),
              );
              return null;
            },
          ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (DismissIntent intent) {
              Navigator.of(context).maybePop();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: scaffold),
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

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.black54,
        ),
      ),
    );
  }

  Widget _buildStatusSection(AsyncValue<DrawerStatusSnapshot> statusAsync) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: statusAsync.when(
          data: (DrawerStatusSnapshot value) {
            return Column(
              children: [
                ListTile(
                  dense: true,
                  title: const Text(AppStrings.navStatusTitle),
                  trailing: IconButton(
                    tooltip: AppStrings.navRefresh,
                    onPressed: () => ref.invalidate(drawerStatusProvider),
                    icon: const Icon(Icons.refresh),
                  ),
                ),
                _statusTile(
                  label: 'AI',
                  value: value.aiReady
                      ? AppStrings.statusConfigured
                      : AppStrings.statusNotConfigured,
                  error: value.aiError,
                ),
                _statusTile(
                  label: '同步',
                  value: value.syncLastAt == null
                      ? AppStrings.statusNever
                      : _formatTs(value.syncLastAt!),
                  error: value.syncError,
                ),
                _statusTile(
                  label: '备份',
                  value:
                      '上次 ${value.backupLastAt == null ? AppStrings.statusNever : _formatTs(value.backupLastAt!)} / 下次 ${_formatDt(value.backupNextPromptAt)}',
                  error: value.backupError,
                ),
                _statusTile(
                  label: '通知',
                  value: 'pending ${value.notifyPending}',
                  error: '',
                ),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: Text('状态加载中...')),
          ),
          error: (Object error, StackTrace stackTrace) =>
              _statusTile(label: '状态', value: '加载失败', error: '$error'),
        ),
      ),
    );
  }

  Widget _statusTile({
    required String label,
    required String value,
    required String error,
  }) {
    final bool hasError = error.trim().isNotEmpty;
    return ListTile(
      dense: true,
      title: Text('$label: $value'),
      subtitle: Text(
        '错误：${hasError ? error : AppStrings.statusNoError}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: hasError
          ? IconButton(
              tooltip: AppStrings.statusCopyError,
              icon: const Icon(Icons.copy_outlined, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: error));
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text(AppStrings.statusCopied)),
                );
              },
            )
          : null,
    );
  }

  String _formatTs(int value) {
    return _formatDt(DateTime.fromMillisecondsSinceEpoch(value).toLocal());
  }

  String _formatDt(DateTime dt) {
    final String month = dt.month.toString().padLeft(2, '0');
    final String day = dt.day.toString().padLeft(2, '0');
    final String hour = dt.hour.toString().padLeft(2, '0');
    final String minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$month-$day $hour:$minute';
  }
}

class _FocusInboxIntent extends Intent {
  const _FocusInboxIntent();
}

class _OpenSearchIntent extends Intent {
  const _OpenSearchIntent();
}
