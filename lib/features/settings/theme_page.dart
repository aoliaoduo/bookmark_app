import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/theme_builder.dart';
import '../../core/theme/theme_models.dart';
import '../../core/theme/theme_providers.dart';
import '../../core/theme/theme_registry.dart';

class ThemePage extends ConsumerWidget {
  const ThemePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeAsync = ref.watch(themeSelectionProvider);
    final ThemeSelection selection = switch (themeAsync) {
      AsyncData<ThemeSelection>(:final value) => value,
      _ => ThemeSelection.defaults,
    };

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.themePageTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            AppStrings.themeModeTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SegmentedButton<AppThemeMode>(
            segments: const <ButtonSegment<AppThemeMode>>[
              ButtonSegment<AppThemeMode>(
                value: AppThemeMode.system,
                label: Text(AppStrings.themeModeSystem),
              ),
              ButtonSegment<AppThemeMode>(
                value: AppThemeMode.light,
                label: Text(AppStrings.themeModeLight),
              ),
              ButtonSegment<AppThemeMode>(
                value: AppThemeMode.dark,
                label: Text(AppStrings.themeModeDark),
              ),
            ],
            selected: <AppThemeMode>{selection.mode},
            onSelectionChanged: (Set<AppThemeMode> values) {
              ref.read(themeSelectionProvider.notifier).setMode(values.first);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text(AppStrings.themeSaveSuccess)),
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            AppStrings.themePresetTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...ThemeRegistry.presets.map((ThemePresetTokens preset) {
            final bool selected = preset.id == selection.presetId;
            return Card(
              child: InkWell(
                onTap: () {
                  ref
                      .read(themeSelectionProvider.notifier)
                      .setPreset(preset.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text(AppStrings.themeSaveSuccess)),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(preset.displayName),
                            Text(
                              'id: ${preset.id}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      _ThemeSwatchPreview(selected: selected, preset: preset),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ThemeSwatchPreview extends StatelessWidget {
  const _ThemeSwatchPreview({required this.selected, required this.preset});

  final bool selected;
  final ThemePresetTokens preset;

  @override
  Widget build(BuildContext context) {
    final ThemeData light = buildThemeData(
      tokens: preset,
      brightness: Brightness.light,
    );
    final ThemeData dark = buildThemeData(
      tokens: preset,
      brightness: Brightness.dark,
    );
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: selected ? 1 : 0.72,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dot(light.colorScheme.primary),
          const SizedBox(width: 4),
          _dot(light.scaffoldBackgroundColor),
          const SizedBox(width: 4),
          _dot(dark.colorScheme.primary),
          const SizedBox(width: 4),
          _dot(dark.scaffoldBackgroundColor),
        ],
      ),
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
    );
  }
}
