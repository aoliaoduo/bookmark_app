class SensitiveDataSanitizer {
  SensitiveDataSanitizer._();

  static const Set<String> _sensitiveKeys = <String>{
    'password',
    'passwd',
    'pwd',
    'token',
    'access_token',
    'refresh_token',
    'authorization',
    'api_key',
    'apikey',
    'secret',
    'username',
    'user',
  };

  static String sanitizeText(String input) {
    if (input.isEmpty) {
      return input;
    }

    String sanitized = input;
    sanitized = _sanitizeAuthSchemes(sanitized);
    sanitized = _sanitizeJsonFields(sanitized);
    sanitized = _sanitizeKeyValuePairs(sanitized);
    sanitized = _sanitizeUrls(sanitized);
    return sanitized;
  }

  static String sanitizeObject(Object? input) {
    if (input == null) {
      return '';
    }
    return sanitizeText(input.toString());
  }

  static String _sanitizeAuthSchemes(String input) {
    String output = input.replaceAllMapped(
      RegExp(
        r'\b(Basic)\s+[A-Za-z0-9+/=._-]+',
        caseSensitive: false,
      ),
      (Match m) => '${m.group(1)} ***',
    );
    output = output.replaceAllMapped(
      RegExp(
        r'\b(Bearer)\s+[A-Za-z0-9\-._~+/]+=*',
        caseSensitive: false,
      ),
      (Match m) => '${m.group(1)} ***',
    );
    return output;
  }

  static String _sanitizeKeyValuePairs(String input) {
    return input.replaceAllMapped(
      RegExp(
        r'''\b(password|passwd|pwd|token|access_token|refresh_token|api[_-]?key|secret|username|user)\b\s*([:=])\s*(".*?"|'.*?'|[^,\s;&]+)''',
        caseSensitive: false,
      ),
      (Match m) => '${m.group(1)}${m.group(2)}***',
    );
  }

  static String _sanitizeJsonFields(String input) {
    return input.replaceAllMapped(
      RegExp(
        r'''"(password|passwd|pwd|token|access_token|refresh_token|authorization|api[_-]?key|secret|username|user)"\s*:\s*(".*?"|'.*?')''',
        caseSensitive: false,
      ),
      (Match m) => '"${m.group(1)}":"***"',
    );
  }

  static String _sanitizeUrls(String input) {
    return input.replaceAllMapped(
      RegExp(r'https?://[^\s,\]\)]+', caseSensitive: false),
      (Match m) {
        final String raw = m.group(0) ?? '';
        if (raw.isEmpty) {
          return raw;
        }
        return _sanitizeSingleUrl(raw);
      },
    );
  }

  static String _sanitizeSingleUrl(String raw) {
    final Match? trailingMatch = RegExp(r'([.;:!?]+)$').firstMatch(raw);
    final String trailing = trailingMatch?.group(1) ?? '';
    final String candidate =
        trailing.isEmpty ? raw : raw.substring(0, raw.length - trailing.length);

    final Uri? uri = Uri.tryParse(candidate);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return raw;
    }

    final String query = _sanitizeQuery(uri.query);
    final Uri rebuilt = uri.replace(
      userInfo: uri.userInfo.isEmpty ? '' : '***',
      query: query.isEmpty ? null : query,
    );
    return '${rebuilt.toString()}$trailing';
  }

  static String _sanitizeQuery(String query) {
    if (query.isEmpty) {
      return query;
    }
    final List<String> pairs = query.split('&');
    final List<String> redacted = <String>[];
    for (final String pair in pairs) {
      if (pair.isEmpty) {
        continue;
      }
      final int eq = pair.indexOf('=');
      final String rawKey = eq < 0 ? pair : pair.substring(0, eq);
      final String key = Uri.decodeQueryComponent(rawKey).toLowerCase();
      if (_sensitiveKeys.contains(key)) {
        redacted.add('$rawKey=***');
      } else {
        redacted.add(pair);
      }
    }
    return redacted.join('&');
  }
}
