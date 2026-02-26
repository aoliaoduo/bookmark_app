import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_shell.dart';
import '../core/db/db_provider.dart';
import '../core/i18n/app_strings.dart';
import '../core/theme/theme_builder.dart';
import '../core/theme/theme_models.dart';
import '../core/theme/theme_providers.dart';
import '../core/theme/theme_registry.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = switch (ref.watch(themeSelectionProvider)) {
      AsyncData<ThemeSelection>(:final value) => value,
      _ => ThemeSelection.defaults,
    };
    final preset = ThemeRegistry.byId(selection.presetId);
    return MaterialApp(
      title: AppStrings.appTitle,
      themeMode: selection.mode.toThemeMode(),
      theme: buildThemeData(tokens: preset, brightness: Brightness.light),
      darkTheme: buildThemeData(tokens: preset, brightness: Brightness.dark),
      home: const AppBootstrap(),
    );
  }
}

class AppBootstrap extends ConsumerWidget {
  const AppBootstrap({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dbAsync = ref.watch(appDatabaseProvider);

    return dbAsync.when(
      data: (_) => const AppShell(),
      loading: () => const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text(AppStrings.loadingDb),
            ],
          ),
        ),
      ),
      error: (error, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('${AppStrings.dbInitFailed}$error'),
          ),
        ),
      ),
    );
  }
}
