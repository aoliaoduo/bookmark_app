class RouterDecision {
  const RouterDecision({
    required this.action,
    required this.confidence,
    required this.payload,
  });

  final String action;
  final double confidence;
  final Map<String, Object?> payload;

  static RouterDecision fromJson(Map<String, Object?> json) {
    return RouterDecision(
      action: json['action'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      payload: (json['payload'] as Map<String, Object?>),
    );
  }
}
