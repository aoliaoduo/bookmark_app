import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/diagnostics_models.dart';
import '../../core/diagnostics/diagnostics_providers.dart';
import '../../core/diagnostics/diagnostics_service.dart';
import '../../core/i18n/app_strings.dart';

class AboutDiagnosticsPage extends ConsumerStatefulWidget {
  const AboutDiagnosticsPage({super.key});

  @override
  ConsumerState<AboutDiagnosticsPage> createState() =>
      _AboutDiagnosticsPageState();
}

class _AboutDiagnosticsPageState extends ConsumerState<AboutDiagnosticsPage> {
  static const String _appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '0.1.0-beta.1+1',
  );
  static const String _gitCommit = String.fromEnvironment(
    'GIT_COMMIT',
    defaultValue: 'unknown',
  );

  bool _loaded = false;
  bool _working = false;
  bool _includeSensitive = false;
  String _status = '';
  String _summary = '';
  String _zipPath = '';
  DiagnosticsStatusSnapshot? _snapshot;

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _refreshSnapshot();
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.diagnosticsPageTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Version $_appVersion',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          SelectableText(
            'Commit ${_gitCommit.trim().isEmpty ? 'unknown' : _gitCommit.trim()}',
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: _includeSensitive,
            onChanged: _working
                ? null
                : (bool value) {
                    setState(() {
                      _includeSensitive = value;
                    });
                  },
            title: const Text(AppStrings.diagnosticsIncludeSensitiveTitle),
            subtitle: const Text(AppStrings.diagnosticsIncludeSensitiveDesc),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _working ? null : _exportBundle,
                child: Text(
                  _working
                      ? AppStrings.diagnosticsExporting
                      : AppStrings.diagnosticsExportZip,
                ),
              ),
              OutlinedButton(
                onPressed: _working ? null : _copySummary,
                child: const Text(AppStrings.diagnosticsCopySummary),
              ),
              OutlinedButton(
                onPressed: _working ? null : _refreshSnapshot,
                child: const Text(AppStrings.diagnosticsRefreshStatus),
              ),
            ],
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_status),
          ],
          if (_zipPath.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              '${AppStrings.diagnosticsExportPathPrefix}$_zipPath',
            ),
          ],
          if (_summary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              AppStrings.diagnosticsSummaryTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            SelectableText(_summary),
          ],
          const SizedBox(height: 16),
          Text(
            AppStrings.navStatusTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          _buildStatusCard(context),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final DiagnosticsStatusSnapshot? value = _snapshot;
    if (value == null) {
      return const Text(AppStrings.loadingDb);
    }
    return Card(
      child: Column(
        children: [
          _statusTile(
            label: 'AI',
            value: value.aiConfigured
                ? AppStrings.statusConfigured
                : AppStrings.statusNotConfigured,
            error: value.aiError,
          ),
          _statusTile(
            label: AppStrings.settingsGroupSync,
            value: value.syncLastAt == null ? '-' : _fmtTs(value.syncLastAt!),
            error: value.syncError,
          ),
          _statusTile(
            label: AppStrings.settingsGroupBackup,
            value:
                '${value.backupLastAt == null ? '-' : _fmtTs(value.backupLastAt!)} / ${_fmtDt(value.backupNextPromptAt)}',
            error: value.backupError,
          ),
          _statusTile(
            label: AppStrings.settingsGroupNotify,
            value: 'pending ${value.notifyPending}',
            error: value.notifyError,
          ),
        ],
      ),
    );
  }

  Widget _statusTile({
    required String label,
    required String value,
    required String error,
  }) {
    final String trimmedError = error.trim();
    return ListTile(
      dense: true,
      title: Text('$label: $value'),
      subtitle: Text(
        trimmedError.isEmpty ? AppStrings.statusNoError : trimmedError,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trimmedError.isEmpty
          ? null
          : IconButton(
              tooltip: AppStrings.statusCopyError,
              icon: const Icon(Icons.copy_outlined, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: trimmedError));
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text(AppStrings.statusCopied)),
                );
              },
            ),
    );
  }

  Future<void> _refreshSnapshot() async {
    final DiagnosticsService service = ref.read(diagnosticsServiceProvider);
    final DiagnosticsStatusSnapshot snapshot = await service.loadSnapshot();
    final String summary = await service.buildSummaryText(
      includeSensitive: _includeSensitive,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = snapshot;
      _summary = summary;
      _status = AppStrings.diagnosticsRefreshed;
    });
  }

  Future<void> _exportBundle() async {
    if (_includeSensitive && !await _confirmSensitiveExport()) {
      return;
    }
    setState(() {
      _working = true;
      _status = AppStrings.diagnosticsExporting;
    });
    try {
      final DiagnosticsService service = ref.read(diagnosticsServiceProvider);
      final DiagnosticsExportResult result = await service.exportBundle(
        includeSensitive: _includeSensitive,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _working = false;
        _zipPath = result.zipPath;
        _summary = result.summary;
        _status = '${AppStrings.diagnosticsExportDonePrefix}${result.zipPath}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _working = false;
        _status = '${AppStrings.diagnosticsExportFailedPrefix}$error';
      });
    }
  }

  Future<bool> _confirmSensitiveExport() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(AppStrings.diagnosticsSensitiveConfirmTitle),
          content: const Text(AppStrings.diagnosticsSensitiveConfirmBody),
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
    return confirmed == true;
  }

  Future<void> _copySummary() async {
    final DiagnosticsService service = ref.read(diagnosticsServiceProvider);
    final String summary = _summary.isNotEmpty
        ? _summary
        : await service.buildSummaryText(includeSensitive: _includeSensitive);
    await Clipboard.setData(ClipboardData(text: summary));
    if (!mounted) {
      return;
    }
    setState(() {
      _summary = summary;
      _status = AppStrings.diagnosticsSummaryCopied;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(AppStrings.statusCopied)));
  }

  String _fmtTs(int value) {
    return _fmtDt(DateTime.fromMillisecondsSinceEpoch(value).toLocal());
  }

  String _fmtDt(DateTime dt) {
    final String month = dt.month.toString().padLeft(2, '0');
    final String day = dt.day.toString().padLeft(2, '0');
    final String hour = dt.hour.toString().padLeft(2, '0');
    final String minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$month-$day $hour:$minute';
  }
}
