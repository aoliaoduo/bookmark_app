import 'package:code/core/notify/feishu_sender.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'buildFeishuWebhookPayload contains msg body and optional signature',
    () {
      final Map<String, Object?> unsigned = buildFeishuWebhookPayload(
        text: 'hello',
      );
      expect(unsigned['msg_type'], 'text');
      expect(unsigned['timestamp'], isNull);
      expect(unsigned['sign'], isNull);

      final Map<String, Object?> signed = buildFeishuWebhookPayload(
        text: 'hello',
        secret: 'abc123',
        timestampSeconds: 1700000000,
      );
      expect(signed['msg_type'], 'text');
      expect((signed['content'] as Map<String, Object?>)['text'], 'hello');
      expect(signed['timestamp'], '1700000000');
      final String sign = (signed['sign'] as String?) ?? '';
      expect(sign, isNotEmpty);
    },
  );
}
