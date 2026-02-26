import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/maintenance/maintenance_providers.dart';
import '../../core/maintenance/maintenance_service.dart';

class MaintenancePage extends ConsumerStatefulWidget {
  const MaintenancePage({super.key});

  @override
  ConsumerState<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends ConsumerState<MaintenancePage> {
  final TextEditingController _daysController = TextEditingController(
    text: '30',
  );
  bool _working = false;
  String _status = '';

  @override
  void dispose() {
    _daysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.maintenancePageTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _daysController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: AppStrings.maintenanceDeletedDaysLabel,
            ),
          ),
          const SizedBox(height: 12),
          _actionButton(
            label: AppStrings.maintenancePurgeDeleted,
            onPressed: _working
                ? null
                : () => _runWithConfirm(
                    title: AppStrings.maintenancePurgeDeleted,
                    action: _purgeDeleted,
                  ),
          ),
          const SizedBox(height: 8),
          _actionButton(
            label: AppStrings.maintenancePurgeTags,
            onPressed: _working
                ? null
                : () => _runWithConfirm(
                    title: AppStrings.maintenancePurgeTags,
                    action: _purgeTags,
                  ),
          ),
          const SizedBox(height: 8),
          _actionButton(
            label: AppStrings.maintenanceRebuildFts,
            onPressed: _working
                ? null
                : () => _runWithConfirm(
                    title: AppStrings.maintenanceRebuildFts,
                    action: _rebuildFts,
                  ),
          ),
          const SizedBox(height: 8),
          _actionButton(
            label: AppStrings.maintenanceVacuum,
            onPressed: _working
                ? null
                : () => _runWithConfirm(
                    title: AppStrings.maintenanceVacuum,
                    action: _optimizeVacuum,
                  ),
          ),
          const SizedBox(height: 8),
          _actionButton(
            label: AppStrings.maintenancePurgeNoteHistory,
            onPressed: _working
                ? null
                : () => _runWithConfirm(
                    title: AppStrings.maintenancePurgeNoteHistory,
                    action: _purgeNoteHistory,
                  ),
          ),
          const SizedBox(height: 14),
          if (_status.isNotEmpty) Text(_status),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return FilledButton.tonal(onPressed: onPressed, child: Text(label));
  }

  Future<void> _runWithConfirm({
    required String title,
    required Future<MaintenanceResult> Function() action,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(AppStrings.maintenanceConfirmTitle),
          content: Text(title),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(AppStrings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(AppStrings.confirm),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _working = true;
      _status = AppStrings.maintenanceWorking;
    });
    try {
      final MaintenanceResult result = await action();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = '${AppStrings.maintenanceDone}：${result.summary}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = '${AppStrings.maintenanceFailedPrefix}$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<MaintenanceResult> _purgeDeleted() {
    final int days = int.tryParse(_daysController.text.trim()) ?? 30;
    return ref
        .read(maintenanceServiceProvider)
        .purgeSoftDeleted(olderThanDays: days.clamp(1, 3650));
  }

  Future<MaintenanceResult> _purgeTags() {
    return ref.read(maintenanceServiceProvider).purgeOrphanTags();
  }

  Future<MaintenanceResult> _rebuildFts() {
    return ref.read(maintenanceServiceProvider).rebuildFts();
  }

  Future<MaintenanceResult> _optimizeVacuum() {
    return ref.read(maintenanceServiceProvider).optimizeVacuum();
  }

  Future<MaintenanceResult> _purgeNoteHistory() {
    return ref.read(maintenanceServiceProvider).purgeNoteHistoryKeepLatest();
  }
}
