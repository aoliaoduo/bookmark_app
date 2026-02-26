import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

final FutureProvider<AppDatabase> appDatabaseProvider =
    FutureProvider<AppDatabase>((Ref ref) async {
      final AppDatabase database = await AppDatabase.open();
      ref.onDispose(() {
        unawaited(database.close());
      });
      return database;
    });
