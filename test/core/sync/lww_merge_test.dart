import 'package:code/core/sync/lww.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('higher lamport wins', () {
    final decision = compareLww(
      localLamport: 10,
      localDeviceId: 'device_a',
      remoteLamport: 11,
      remoteDeviceId: 'device_b',
    );
    expect(decision, LwwDecision.takeRemote);
  });

  test('same lamport uses device_id as tie breaker', () {
    final decision = compareLww(
      localLamport: 10,
      localDeviceId: 'device_z',
      remoteLamport: 10,
      remoteDeviceId: 'device_a',
    );
    expect(decision, LwwDecision.keepLocal);
  });
}
