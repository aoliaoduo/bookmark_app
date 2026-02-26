class AiProviderConfig {
  const AiProviderConfig({
    required this.baseUrl,
    required this.apiRoot,
    required this.apiKey,
    required this.selectedModel,
    required this.storedRiskConfirmed,
  });

  static const AiProviderConfig empty = AiProviderConfig(
    baseUrl: '',
    apiRoot: '',
    apiKey: '',
    selectedModel: '',
    storedRiskConfirmed: false,
  );

  final String baseUrl;
  final String apiRoot;
  final String apiKey;
  final String selectedModel;
  final bool storedRiskConfirmed;

  bool get isReady => apiRoot.isNotEmpty && apiKey.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'base_url': baseUrl,
    'api_root': apiRoot,
    'api_key': apiKey,
    'selected_model': selectedModel,
    'risk_confirmed': storedRiskConfirmed,
  };

  static AiProviderConfig fromJson(Map<String, Object?> json) {
    return AiProviderConfig(
      baseUrl: (json['base_url'] as String?) ?? '',
      apiRoot: (json['api_root'] as String?) ?? '',
      apiKey: (json['api_key'] as String?) ?? '',
      selectedModel: (json['selected_model'] as String?) ?? '',
      storedRiskConfirmed: (json['risk_confirmed'] as bool?) ?? false,
    );
  }

  AiProviderConfig copyWith({
    String? baseUrl,
    String? apiRoot,
    String? apiKey,
    String? selectedModel,
    bool? storedRiskConfirmed,
  }) {
    return AiProviderConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiRoot: apiRoot ?? this.apiRoot,
      apiKey: apiKey ?? this.apiKey,
      selectedModel: selectedModel ?? this.selectedModel,
      storedRiskConfirmed: storedRiskConfirmed ?? this.storedRiskConfirmed,
    );
  }
}
