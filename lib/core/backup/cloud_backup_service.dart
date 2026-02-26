import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../clock/app_clock.dart';
import '../db/app_database.dart';
import '../db/migrations.dart';
import '../identity/device_identity_service.dart';
import '../sync/webdav/webdav_config.dart';
import '../sync/webdav/webdav_storage_client.dart';
import 'backup_manifest.dart';

class CloudBackupService {
  CloudBackupService({
    required this.database,
    required this.clock,
    required this.identityService,
  });

  static final Logger _log = Logger('CloudBackupService');
  static const String _backupDir = 'backups';
  static const String _dbEntryName = 'db.sqlite';
  static const String _manifestEntryName = 'manifest.json';
  static const String _appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0+1',
  );

  final AppDatabase database;
  final AppClock clock;
  final DeviceIdentityService identityService;

  Future<BackupRunResult> createAndUploadBackup({
    required WebDavConfig config,
    int retentionCount = 30,
  }) async {
    if (!config.isReady) {
      throw Exception('WebDAV 配置不完整');
    }
    final WebDavStorageClient client = WebDavStorageClient(config: config);
    await client.ensureDirectory(_backupDir);

    final BackupManifest manifest = await _buildManifest();
    final Uint8List zipBytes = await _buildZipBytes(manifest);
    final String fileName = _buildBackupFileName(manifest.createdAt);
    final String remotePath = '$_backupDir/$fileName';
    await client.uploadBytes(
      remotePath,
      zipBytes,
      contentType: 'application/zip',
    );

    final List<CloudBackupItem> backups = await listCloudBackups(config);
    if (backups.length > retentionCount) {
      final List<CloudBackupItem> extras = backups
          .skip(retentionCount)
          .toList(growable: false);
      for (final CloudBackupItem extra in extras) {
        await client.delete(extra.remotePath);
      }
    }
    await database.db.insert('kv', <String, Object?>{
      'key': 'backup_last_success_at',
      'value': '${manifest.createdAt}',
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    _log.info('云备份完成: $remotePath');
    return BackupRunResult(remotePath: remotePath, manifest: manifest);
  }

  Future<Uint8List> buildBackupZipBytesForTesting() async {
    final BackupManifest manifest = await _buildManifest();
    return _buildZipBytes(manifest);
  }

  Future<List<CloudBackupItem>> listCloudBackups(WebDavConfig config) async {
    if (!config.isReady) {
      return const <CloudBackupItem>[];
    }
    final WebDavStorageClient client = WebDavStorageClient(config: config);
    await client.ensureDirectory(_backupDir);
    final List<WebDavFileEntry> entries = await client.listDirectory(
      _backupDir,
    );
    final List<CloudBackupItem> items =
        entries
            .where(
              (WebDavFileEntry e) => !e.isCollection && e.path.endsWith('.zip'),
            )
            .map((WebDavFileEntry e) {
              final String name = p.basename(e.path);
              return CloudBackupItem(
                remotePath: e.path,
                fileName: name,
                sizeBytes: e.sizeBytes,
                lastModified: e.lastModified,
              );
            })
            .toList(growable: false)
          ..sort((a, b) => b.fileName.compareTo(a.fileName));
    return items;
  }

  Future<RestoreRunResult> restoreFromCloud({
    required WebDavConfig config,
    required CloudBackupItem backup,
  }) async {
    if (!config.isReady) {
      throw Exception('WebDAV 配置不完整');
    }
    final WebDavStorageClient client = WebDavStorageClient(config: config);
    final Uint8List bytes = await client.downloadBytes(backup.remotePath);
    return restoreFromZipBytes(bytes);
  }

  Future<RestoreRunResult> restoreFromZipBytes(Uint8List zipBytes) async {
    final Archive archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
    final ArchiveFile dbFile = archive.files.firstWhere(
      (ArchiveFile e) => e.name == _dbEntryName,
      orElse: () => ArchiveFile.noCompress(_dbEntryName, 0, Uint8List(0)),
    );
    final ArchiveFile manifestFile = archive.files.firstWhere(
      (ArchiveFile e) => e.name == _manifestEntryName,
      orElse: () => ArchiveFile.noCompress(_manifestEntryName, 0, Uint8List(0)),
    );
    if (dbFile.size <= 0 || manifestFile.size <= 0) {
      throw Exception('备份包结构无效，缺少 db.sqlite 或 manifest.json');
    }

    final Uint8List manifestBytes = _toBytes(manifestFile.content);
    final Object? decoded = jsonDecode(utf8.decode(manifestBytes));
    if (decoded is! Map<String, Object?>) {
      throw Exception('manifest.json 解析失败');
    }
    final BackupManifest manifest = BackupManifest.fromJson(decoded);
    if (manifest.schemaVersion > kCurrentDbVersion) {
      throw Exception('备份 schema_version 过高，当前版本无法恢复');
    }

    final String dbPath = database.db.path;
    final String localTempBackupPath =
        '$dbPath.pre_restore_${clock.nowMs()}.bak';
    await File(dbPath).copy(localTempBackupPath);

    final Directory tempDir = await Directory.systemTemp.createTemp('restore_');
    final String sourceDbPath = p.join(tempDir.path, 'source.db');
    await File(
      sourceDbPath,
    ).writeAsBytes(_toBytes(dbFile.content), flush: true);

    final AppDatabase sourceDb = await AppDatabase.open(
      databasePath: sourceDbPath,
    );
    try {
      await _replaceCurrentDataFromSource(sourceDb);
    } finally {
      await sourceDb.close();
      await tempDir.delete(recursive: true);
    }

    _log.info('云恢复完成，临时本地备份: $localTempBackupPath');
    return RestoreRunResult(
      manifest: manifest,
      localTempBackupPath: localTempBackupPath,
    );
  }

  Future<BackupManifest> _buildManifest() async {
    final String deviceId = await identityService.getOrCreateDeviceId(
      database.db,
    );
    return BackupManifest(
      schemaVersion: kCurrentDbVersion,
      appVersion: _appVersion,
      deviceId: deviceId,
      createdAt: clock.nowMs(),
    );
  }

  Future<Uint8List> _buildZipBytes(BackupManifest manifest) async {
    final File dbFile = File(database.db.path);
    final Uint8List dbBytes = await dbFile.readAsBytes();
    final Uint8List manifestBytes = Uint8List.fromList(
      utf8.encode(jsonEncode(manifest.toJson())),
    );

    final Archive archive = Archive();
    archive.addFile(ArchiveFile(_dbEntryName, dbBytes.length, dbBytes));
    archive.addFile(
      ArchiveFile(_manifestEntryName, manifestBytes.length, manifestBytes),
    );
    final List<int> encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }

  Future<void> _replaceCurrentDataFromSource(AppDatabase sourceDb) async {
    final List<String> tables = await _loadSourceTables(sourceDb);
    await database.db.transaction((txn) async {
      for (final String table in tables) {
        if (table.startsWith('sqlite_')) {
          continue;
        }
        await txn.delete(table);
        final List<Map<String, Object?>> rows = await sourceDb.db.query(table);
        for (final Map<String, Object?> row in rows) {
          await txn.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  Future<List<String>> _loadSourceTables(AppDatabase sourceDb) async {
    final List<Map<String, Object?>> rows = await sourceDb.db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type='table'
      ORDER BY name ASC
      ''');
    return rows
        .map((Map<String, Object?> row) => row['name']! as String)
        .toList(growable: false);
  }

  Uint8List _toBytes(Object? content) {
    if (content is Uint8List) {
      return content;
    }
    if (content is List<int>) {
      return Uint8List.fromList(content);
    }
    if (content is String) {
      return Uint8List.fromList(utf8.encode(content));
    }
    return Uint8List(0);
  }

  String _buildBackupFileName(int createdAt) {
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(
      createdAt,
    ).toLocal();
    final String y = dt.year.toString();
    final String m = dt.month.toString().padLeft(2, '0');
    final String d = dt.day.toString().padLeft(2, '0');
    final String h = dt.hour.toString().padLeft(2, '0');
    final String min = dt.minute.toString().padLeft(2, '0');
    final String s = dt.second.toString().padLeft(2, '0');
    return 'backup_$y$m${d}_$h$min$s.zip';
  }
}
