import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'app/app.dart';

void main() {
  _configureLogging();
  runApp(const ProviderScope(child: App()));
}

void _configureLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord record) {
    debugPrint(
      '[${record.time.toIso8601String()}] ${record.loggerName} '
      '${record.level.name}: ${record.message}',
    );
  });
}
