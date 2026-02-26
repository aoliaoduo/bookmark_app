import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentityService {
  static const String _deviceIdKey = 'device_id';
  static const Uuid _uuid = Uuid();

  Future<String> getOrCreateDeviceId(DatabaseExecutor db) async {
    final List<Map<String, Object?>> rows = await db.query(
      'kv',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: const <Object?>[_deviceIdKey],
      limit: 1,
    );

    if (rows.isNotEmpty) {
      final String? value = rows.first['value']?.toString();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    final String deviceId = _uuid.v4();
    await db.insert('kv', {'key': _deviceIdKey, 'value': deviceId});
    return deviceId;
  }
}
