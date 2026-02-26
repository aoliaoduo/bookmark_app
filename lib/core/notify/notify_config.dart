class FeishuNotifyConfig {
  const FeishuNotifyConfig({
    required this.enabled,
    required this.webhookUrl,
    required this.secret,
  });

  static const FeishuNotifyConfig empty = FeishuNotifyConfig(
    enabled: false,
    webhookUrl: '',
    secret: '',
  );

  final bool enabled;
  final String webhookUrl;
  final String secret;

  bool get isReady => enabled && webhookUrl.trim().isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enabled': enabled,
      'webhook_url': webhookUrl,
      'secret': secret,
    };
  }

  factory FeishuNotifyConfig.fromJson(Map<String, Object?> map) {
    return FeishuNotifyConfig(
      enabled: map['enabled'] == true,
      webhookUrl: (map['webhook_url'] as String?) ?? '',
      secret: (map['secret'] as String?) ?? '',
    );
  }
}

class SmtpNotifyConfig {
  const SmtpNotifyConfig({
    required this.enabled,
    required this.host,
    required this.port,
    required this.useTls,
    required this.username,
    required this.password,
    required this.from,
    required this.to,
  });

  static const SmtpNotifyConfig empty = SmtpNotifyConfig(
    enabled: false,
    host: '',
    port: 465,
    useTls: true,
    username: '',
    password: '',
    from: '',
    to: '',
  );

  final bool enabled;
  final String host;
  final int port;
  final bool useTls;
  final String username;
  final String password;
  final String from;
  final String to;

  bool get isReady =>
      enabled &&
      host.trim().isNotEmpty &&
      from.trim().isNotEmpty &&
      to.trim().isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enabled': enabled,
      'host': host,
      'port': port,
      'use_tls': useTls,
      'username': username,
      'password': password,
      'from': from,
      'to': to,
    };
  }

  factory SmtpNotifyConfig.fromJson(Map<String, Object?> map) {
    return SmtpNotifyConfig(
      enabled: map['enabled'] == true,
      host: (map['host'] as String?) ?? '',
      port: ((map['port'] as num?)?.toInt() ?? 465),
      useTls: map['use_tls'] != false,
      username: (map['username'] as String?) ?? '',
      password: (map['password'] as String?) ?? '',
      from: (map['from'] as String?) ?? '',
      to: (map['to'] as String?) ?? '',
    );
  }
}

class NotifyConfigs {
  const NotifyConfigs({required this.feishu, required this.smtp});

  static const NotifyConfigs empty = NotifyConfigs(
    feishu: FeishuNotifyConfig.empty,
    smtp: SmtpNotifyConfig.empty,
  );

  final FeishuNotifyConfig feishu;
  final SmtpNotifyConfig smtp;
}
