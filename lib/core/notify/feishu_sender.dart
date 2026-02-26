import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'notify_config.dart';

Map<String, Object?> buildFeishuWebhookPayload({
  required String text,
  String? secret,
  int? timestampSeconds,
}) {
  final Map<String, Object?> payload = <String, Object?>{
    'msg_type': 'text',
    'content': <String, Object?>{'text': text},
  };
  final String trimmedSecret = (secret ?? '').trim();
  if (trimmedSecret.isNotEmpty) {
    final int ts =
        timestampSeconds ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final String toSign = '$ts\n$trimmedSecret';
    final Hmac mac = Hmac(sha256, utf8.encode(trimmedSecret));
    final String signature = base64Encode(
      mac.convert(utf8.encode(toSign)).bytes,
    );
    payload['timestamp'] = '$ts';
    payload['sign'] = signature;
  }
  return payload;
}

class FeishuSender {
  FeishuSender({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<void> send({
    required FeishuNotifyConfig config,
    required String title,
    required String message,
  }) async {
    if (!config.isReady) {
      throw Exception('飞书通道未配置');
    }
    final Uri uri = Uri.parse(config.webhookUrl.trim());
    final String text = '$title\n$message';
    final Map<String, Object?> payload = buildFeishuWebhookPayload(
      text: text,
      secret: config.secret,
    );
    final http.Response response = await _client.post(
      uri,
      headers: const <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('飞书请求失败: ${response.statusCode}');
    }

    if (response.body.trim().isEmpty) {
      return;
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return;
    }
    final int? code =
        (decoded['code'] as num?)?.toInt() ??
        (decoded['StatusCode'] as num?)?.toInt();
    if (code != null && code != 0) {
      final String msg = (decoded['msg'] ?? decoded['StatusMessage'] ?? '')
          .toString();
      throw Exception('飞书返回失败 code=$code $msg');
    }
  }
}
