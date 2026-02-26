import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/db_provider.dart';
import 'theme_models.dart';
import 'theme_repository.dart';
import 'theme_registry.dart';

final AsyncNotifierProvider<ThemeSelectionController, ThemeSelection>
themeSelectionProvider =
    AsyncNotifierProvider<ThemeSelectionController, ThemeSelection>(
      ThemeSelectionController.new,
    );

class ThemeSelectionController extends AsyncNotifier<ThemeSelection> {
  @override
  Future<ThemeSelection> build() async {
    final database = await ref.watch(appDatabaseProvider.future);
    return ThemeRepository(database).load();
  }

  Future<void> setMode(AppThemeMode mode) async {
    final ThemeSelection current = _currentOrDefaults();
    final ThemeSelection next = current.copyWith(mode: mode);
    await _save(next);
  }

  Future<void> setPreset(String presetId) async {
    final ThemeSelection current = _currentOrDefaults();
    final ThemeSelection next = current.copyWith(
      presetId: ThemeRegistry.byId(presetId).id,
    );
    await _save(next);
  }

  Future<void> _save(ThemeSelection selection) async {
    final database = await ref.read(appDatabaseProvider.future);
    await ThemeRepository(database).save(selection);
    state = AsyncData<ThemeSelection>(selection);
  }

  ThemeSelection _currentOrDefaults() {
    final AsyncValue<ThemeSelection> current = state;
    return switch (current) {
      AsyncData<ThemeSelection>(:final value) => value,
      _ => ThemeSelection.defaults,
    };
  }
}
