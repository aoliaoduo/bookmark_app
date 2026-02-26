import 'package:mailer/mailer.dart' as mailer;
import 'package:mailer/smtp_server.dart';

import 'notify_config.dart';

class SmtpSender {
  Future<void> send({
    required SmtpNotifyConfig config,
    required String title,
    required String message,
  }) async {
    if (!config.isReady) {
      throw Exception('SMTP 通道未配置');
    }
    final List<String> recipients = config.to
        .split(RegExp(r'[;, \n]+'))
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);
    if (recipients.isEmpty) {
      throw Exception('SMTP 收件人为空');
    }
    final SmtpServer server = SmtpServer(
      config.host.trim(),
      port: config.port,
      ssl: config.useTls,
      username: config.username.trim().isEmpty ? null : config.username.trim(),
      password: config.password.trim().isEmpty ? null : config.password,
    );
    final mailer.Message mail = mailer.Message()
      ..from = mailer.Address(config.from.trim())
      ..recipients.addAll(recipients)
      ..subject = title
      ..text = message;
    await mailer.send(mail, server);
  }
}
