class WebDavConfig {
  const WebDavConfig({
    required this.baseUrl,
    required this.username,
    required this.appPassword,
    required this.paidPlan,
  });

  static const WebDavConfig empty = WebDavConfig(
    baseUrl: '',
    username: '',
    appPassword: '',
    paidPlan: false,
  );

  final String baseUrl;
  final String username;
  final String appPassword;
  final bool paidPlan;

  bool get isReady =>
      baseUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      appPassword.trim().isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'base_url': baseUrl,
      'username': username,
      'app_password': appPassword,
      'paid_plan': paidPlan,
    };
  }

  factory WebDavConfig.fromJson(Map<String, Object?> map) {
    return WebDavConfig(
      baseUrl: (map['base_url'] as String?) ?? '',
      username: (map['username'] as String?) ?? '',
      appPassword: (map['app_password'] as String?) ?? '',
      paidPlan: map['paid_plan'] == true,
    );
  }

  WebDavConfig copyWith({
    String? baseUrl,
    String? username,
    String? appPassword,
    bool? paidPlan,
  }) {
    return WebDavConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      appPassword: appPassword ?? this.appPassword,
      paidPlan: paidPlan ?? this.paidPlan,
    );
  }
}
