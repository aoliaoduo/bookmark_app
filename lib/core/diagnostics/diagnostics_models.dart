class DiagnosticsStatusSnapshot {
  const DiagnosticsStatusSnapshot({
    required this.aiConfigured,
    required this.aiError,
    required this.syncLastAt,
    required this.syncError,
    required this.backupLastAt,
    required this.backupNextPromptAt,
    required this.backupError,
    required this.notifyPending,
    required this.notifyError,
  });

  final bool aiConfigured;
  final String aiError;
  final int? syncLastAt;
  final String syncError;
  final int? backupLastAt;
  final DateTime backupNextPromptAt;
  final String backupError;
  final int notifyPending;
  final String notifyError;
}

class DiagnosticsExportResult {
  const DiagnosticsExportResult({
    required this.zipPath,
    required this.summary,
    required this.includeSensitive,
  });

  final String zipPath;
  final String summary;
  final bool includeSensitive;
}
