import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../ai/ai_provider_repository.dart';
import '../backup/backup_settings_repository.dart';
import '../clock/app_clock.dart';
import '../db/app_database.dart';
import 'diagnostics_models.dart';

class DiagnosticsService {
  DiagnosticsService({
    required this.database,
    required this.aiProviderRepository,
    required this.backupSettingsRepository,
    required this.clock,
  });

  static const String _defaultRedacted = '<redacted>';
  static const int _recentQueueLogLimit = 80;
  static const String _appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '0.1.0-beta.1+1',
  );
  static const String _gitCommit = String.fromEnvironment(
    'GIT_COMMIT',
    defaultValue: '',
  );

  final AppDatabase database;
  final AiProviderRepository aiProviderRepository;
  final BackupSettingsRepository backupSettingsRepository;
  final AppClock clock;

  Future<DiagnosticsExportResult> exportBundle({
    bool includeSensitive = false,
    Directory? outputDirectory,
  }) async {
    final Map<String, Object?> payload = await buildPayload(
      includeSensitive: includeSensitive,
    );
    final String summary = _buildSummaryText(payload);
    final Directory targetDirectory =
        outputDirectory ?? await _resolveOutputDirectory();
    await targetDirectory.create(recursive: true);

    final int nowMs = clock.nowMs();
    final String zipPath = p.join(targetDirectory.path, _buildZipName(nowMs));

    final Uint8List payloadBytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    );
    final Uint8List summaryBytes = Uint8List.fromList(utf8.encode(summary));
    final Archive archive = Archive()
      ..addFile(
        ArchiveFile('diagnostics.json', payloadBytes.length, payloadBytes),
      )
      ..addFile(ArchiveFile('summary.txt', summaryBytes.length, summaryBytes));
    final List<int> encoded = ZipEncoder().encode(archive);
    await File(zipPath).writeAsBytes(encoded, flush: true);
    return DiagnosticsExportResult(
      zipPath: zipPath,
      summary: summary,
      includeSensitive: includeSensitive,
    );
  }

  Future<Map<String, Object?>> buildPayload({
    bool includeSensitive = false,
    int queueLogLimit = _recentQueueLogLimit,
  }) async {
    final int nowMs = clock.nowMs();
    final aiConfig = await aiProviderRepository.load();
    final String aiError = await _loadKv('ai_last_error');
    final String backupError = await _loadKv('backup_last_error');
    final String backupLastRaw = await _loadKv('backup_last_success_at');
    final int? backupLastAt = int.tryParse(backupLastRaw);
    final backupSettings = await backupSettingsRepository.loadSettings();
    final DateTime backupNextPromptAt = _nextBackupPrompt(
      now: DateTime.fromMillisecondsSinceEpoch(nowMs).toLocal(),
      hour: backupSettings.reminderHour,
      minute: backupSettings.reminderMinute,
    );

    final List<Map<String, Object?>> syncRows = await database.db.query(
      'sync_state',
      where: 'id = ?',
      whereArgs: const <Object?>['singleton'],
      limit: 1,
    );
    final Map<String, Object?> syncRow = syncRows.isEmpty
        ? <String, Object?>{}
        : syncRows.first;
    final int? syncLastAt = (syncRow['last_sync_finished_at'] as num?)?.toInt();
    final String syncError = (syncRow['last_error'] as String?) ?? '';

    final List<Map<String, Object?>> queueCountRows = await database.db
        .rawQuery(
          '''
          SELECT COUNT(*) AS c
          FROM notification_jobs
          WHERE status = ?
          ''',
          <Object?>['queued'],
        );
    final int notifyPending = queueCountRows.isEmpty
        ? 0
        : ((queueCountRows.first['c'] as num?)?.toInt() ?? 0);
    final List<Map<String, Object?>> notifyErrorRows = await database.db
        .rawQuery('''
          SELECT last_error
          FROM notification_jobs
          WHERE last_error IS NOT NULL
            AND TRIM(last_error) <> ''
          ORDER BY updated_at DESC
          LIMIT 1
          ''');
    final String notifyError = notifyErrorRows.isEmpty
        ? ''
        : ((notifyErrorRows.first['last_error'] as String?) ?? '');
    final List<Map<String, Object?>> queueLogs = await database.db.rawQuery(
      '''
      SELECT id, channel, status, attempts, next_retry_at, updated_at, created_at, last_error
      FROM notification_jobs
      ORDER BY updated_at DESC, created_at DESC
      LIMIT ?
      ''',
      <Object?>[queueLogLimit],
    );

    final DiagnosticsStatusSnapshot snapshot = DiagnosticsStatusSnapshot(
      aiConfigured: aiConfig.isReady,
      aiError: aiError,
      syncLastAt: syncLastAt,
      syncError: syncError,
      backupLastAt: backupLastAt,
      backupNextPromptAt: backupNextPromptAt,
      backupError: backupError,
      notifyPending: notifyPending,
      notifyError: notifyError,
    );

    return <String, Object?>{
      'meta': <String, Object?>{
        'generated_at': nowMs,
        'app_version': _appVersion,
        'git_commit': _gitCommit.isEmpty ? 'unknown' : _gitCommit,
        'platform': <String, Object?>{
          'os': Platform.operatingSystem,
          'os_version': Platform.operatingSystemVersion,
          'locale': Platform.localeName,
          'dart_version': Platform.version,
          'number_of_processors': Platform.numberOfProcessors,
        },
      },
      'status': <String, Object?>{
        'ai': <String, Object?>{
          'configured': snapshot.aiConfigured,
          'last_error': snapshot.aiError,
        },
        'sync': <String, Object?>{
          'last_sync_finished_at': snapshot.syncLastAt,
          'last_error': snapshot.syncError,
        },
        'backup': <String, Object?>{
          'last_success_at': snapshot.backupLastAt,
          'next_prompt_at': snapshot.backupNextPromptAt.toIso8601String(),
          'last_error': snapshot.backupError,
        },
        'notify': <String, Object?>{
          'pending': snapshot.notifyPending,
          'last_error': snapshot.notifyError,
        },
      },
      'recent_errors': <String, Object?>{
        'ai': snapshot.aiError,
        'sync': snapshot.syncError,
        'backup': snapshot.backupError,
        'notify': snapshot.notifyError,
      },
      'config': <String, Object?>{
        'ai_provider': <String, Object?>{
          'base_url': aiConfig.baseUrl,
          'api_root': aiConfig.apiRoot,
          'selected_model': aiConfig.selectedModel,
          'api_key': includeSensitive ? aiConfig.apiKey : _defaultRedacted,
        },
        'backup': <String, Object?>{
          'reminder_hm': backupSettings.reminderHm,
          'retention_count': backupSettings.retentionCount,
        },
      },
      'sync_summary': <String, Object?>{
        'last_sync_started_at': (syncRow['last_sync_started_at'] as num?)
            ?.toInt(),
        'last_sync_finished_at': (syncRow['last_sync_finished_at'] as num?)
            ?.toInt(),
        'next_allowed_sync_at': (syncRow['next_allowed_sync_at'] as num?)
            ?.toInt(),
        'backoff_until': (syncRow['backoff_until'] as num?)?.toInt(),
        'last_applied_change_id': syncRow['last_applied_change_id'],
        'last_pushed_change_id': syncRow['last_pushed_change_id'],
        'request_count_in_window':
            (syncRow['request_count_in_window'] as num?)?.toInt() ?? 0,
      },
      'backup_summary': <String, Object?>{
        'last_success_at': snapshot.backupLastAt,
        'next_prompt_at': snapshot.backupNextPromptAt.toIso8601String(),
        'last_error': snapshot.backupError,
      },
      'notification_queue': <String, Object?>{
        'pending': snapshot.notifyPending,
        'recent_jobs': queueLogs,
      },
    };
  }

  Future<DiagnosticsStatusSnapshot> loadSnapshot() async {
    final Map<String, Object?> payload = await buildPayload();
    final Map<String, Object?> status =
        payload['status']! as Map<String, Object?>;
    final Map<String, Object?> ai = status['ai']! as Map<String, Object?>;
    final Map<String, Object?> sync = status['sync']! as Map<String, Object?>;
    final Map<String, Object?> backup =
        status['backup']! as Map<String, Object?>;
    final Map<String, Object?> notify =
        status['notify']! as Map<String, Object?>;
    return DiagnosticsStatusSnapshot(
      aiConfigured: ai['configured'] as bool? ?? false,
      aiError: (ai['last_error'] as String?) ?? '',
      syncLastAt: (sync['last_sync_finished_at'] as num?)?.toInt(),
      syncError: (sync['last_error'] as String?) ?? '',
      backupLastAt: (backup['last_success_at'] as num?)?.toInt(),
      backupNextPromptAt:
          DateTime.tryParse((backup['next_prompt_at'] as String?) ?? '') ??
          DateTime.now(),
      backupError: (backup['last_error'] as String?) ?? '',
      notifyPending: (notify['pending'] as num?)?.toInt() ?? 0,
      notifyError: (notify['last_error'] as String?) ?? '',
    );
  }

  Future<String> buildSummaryText({bool includeSensitive = false}) async {
    final Map<String, Object?> payload = await buildPayload(
      includeSensitive: includeSensitive,
    );
    return _buildSummaryText(payload);
  }

  String _buildSummaryText(Map<String, Object?> payload) {
    final Map<String, Object?> meta = payload['meta']! as Map<String, Object?>;
    final Map<String, Object?> status =
        payload['status']! as Map<String, Object?>;
    final Map<String, Object?> ai = status['ai']! as Map<String, Object?>;
    final Map<String, Object?> sync = status['sync']! as Map<String, Object?>;
    final Map<String, Object?> backup =
        status['backup']! as Map<String, Object?>;
    final Map<String, Object?> notify =
        status['notify']! as Map<String, Object?>;

    final StringBuffer buffer = StringBuffer()
      ..writeln('AIOS 诊断摘要')
      ..writeln('app_version: ${meta['app_version'] ?? ''}')
      ..writeln('git_commit: ${meta['git_commit'] ?? 'unknown'}')
      ..writeln(
        'generated_at: ${_fmtTs((meta['generated_at'] as num?)?.toInt())}',
      )
      ..writeln()
      ..writeln(
        'AI: ${(ai['configured'] as bool? ?? false) ? '已配置' : '未配置'} | 错误: ${_safe(ai['last_error'])}',
      )
      ..writeln(
        '同步: 上次 ${_fmtTs((sync['last_sync_finished_at'] as num?)?.toInt())} | 错误: ${_safe(sync['last_error'])}',
      )
      ..writeln(
        '备份: 上次 ${_fmtTs((backup['last_success_at'] as num?)?.toInt())} | 下次 ${backup['next_prompt_at'] ?? '-'} | 错误: ${_safe(backup['last_error'])}',
      )
      ..writeln(
        '通知: pending ${notify['pending'] ?? 0} | 错误: ${_safe(notify['last_error'])}',
      );
    return buffer.toString();
  }

  Future<Directory> _resolveOutputDirectory() async {
    final Directory? downloadDir = await getDownloadsDirectory();
    if (downloadDir != null) {
      return downloadDir;
    }
    return getApplicationDocumentsDirectory();
  }

  Future<String> _loadKv(String key) async {
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

  String _buildZipName(int nowMs) {
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(nowMs).toLocal();
    final String y = dt.year.toString();
    final String m = dt.month.toString().padLeft(2, '0');
    final String d = dt.day.toString().padLeft(2, '0');
    final String h = dt.hour.toString().padLeft(2, '0');
    final String min = dt.minute.toString().padLeft(2, '0');
    final String s = dt.second.toString().padLeft(2, '0');
    return 'aios_diagnostics_${y}_$m${d}_$h$min$s.zip';
  }

  String _fmtTs(int? value) {
    if (value == null || value <= 0) {
      return '-';
    }
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    return dt.toIso8601String();
  }

  String _safe(Object? value) {
    final String raw = (value as String?)?.trim() ?? '';
    return raw.isEmpty ? '-' : raw;
  }
}
