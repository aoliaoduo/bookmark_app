import 'package:code/core/backup/backup_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manifest toJson/fromJson roundtrip', () {
    const BackupManifest manifest = BackupManifest(
      schemaVersion: 3,
      appVersion: '1.2.3+4',
      deviceId: 'device-1',
      createdAt: 1730000000000,
    );
    final BackupManifest decoded = BackupManifest.fromJson(manifest.toJson());
    expect(decoded.schemaVersion, manifest.schemaVersion);
    expect(decoded.appVersion, manifest.appVersion);
    expect(decoded.deviceId, manifest.deviceId);
    expect(decoded.createdAt, manifest.createdAt);
  });
}
