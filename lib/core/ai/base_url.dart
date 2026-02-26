String normalizeBaseUrl(String userInput) {
  final String trimmed = userInput.trim();
  if (trimmed.isEmpty) {
    return '';
  }

  final String withoutTailSlash = trimmed.replaceAll(RegExp(r'/+$'), '');
  if (withoutTailSlash.toLowerCase().endsWith('/v1')) {
    return withoutTailSlash;
  }

  return '$withoutTailSlash/v1';
}
