class BackupManifest {
  const BackupManifest({
    required this.schemaVersion,
    required this.appVersion,
    required this.deviceId,
    required this.createdAt,
  });

  final int schemaVersion;
  final String appVersion;
  final String deviceId;
  final int createdAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema_version': schemaVersion,
      'app_version': appVersion,
      'device_id': deviceId,
      'created_at': createdAt,
    };
  }

  factory BackupManifest.fromJson(Map<String, Object?> map) {
    return BackupManifest(
      schemaVersion: ((map['schema_version'] as num?)?.toInt() ?? 0),
      appVersion: (map['app_version'] as String?) ?? '',
      deviceId: (map['device_id'] as String?) ?? '',
      createdAt: ((map['created_at'] as num?)?.toInt() ?? 0),
    );
  }
}

class CloudBackupItem {
  const CloudBackupItem({
    required this.remotePath,
    required this.fileName,
    this.sizeBytes,
    this.lastModified,
  });

  final String remotePath;
  final String fileName;
  final int? sizeBytes;
  final DateTime? lastModified;
}

class BackupRunResult {
  const BackupRunResult({required this.remotePath, required this.manifest});

  final String remotePath;
  final BackupManifest manifest;
}

class RestoreRunResult {
  const RestoreRunResult({
    required this.manifest,
    required this.localTempBackupPath,
  });

  final BackupManifest manifest;
  final String localTempBackupPath;
}
