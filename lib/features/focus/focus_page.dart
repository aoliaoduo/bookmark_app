import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/focus/focus_timer.dart';
import '../../core/i18n/app_strings.dart';
import 'focus_controller.dart';
import 'focus_providers.dart';

class FocusPage extends ConsumerWidget {
  const FocusPage({super.key});

  static const List<int> _countdownOptionsMinutes = <int>[15, 25, 45, 60];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FocusControllerState state = ref.watch(focusControllerProvider);
    final FocusController controller = ref.read(
      focusControllerProvider.notifier,
    );

    if (!state.initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final FocusTimerSnapshot snapshot = state.snapshot;
    final int displaySeconds = _displaySeconds(snapshot, state.nowMs);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<FocusMode>(
            segments: const <ButtonSegment<FocusMode>>[
              ButtonSegment<FocusMode>(
                value: FocusMode.countdown,
                label: Text(AppStrings.focusModeCountdown),
              ),
              ButtonSegment<FocusMode>(
                value: FocusMode.countup,
                label: Text(AppStrings.focusModeCountup),
              ),
            ],
            selected: <FocusMode>{snapshot.mode},
            onSelectionChanged: (Set<FocusMode> selected) {
              controller.setMode(selected.first);
            },
          ),
          const SizedBox(height: 12),
          if (snapshot.mode == FocusMode.countdown)
            Row(
              children: [
                const Text(AppStrings.focusDurationLabel),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: snapshot.focusDurationSeconds ~/ 60,
                  items: _countdownOptionsMinutes
                      .map(
                        (int minute) => DropdownMenuItem<int>(
                          value: minute,
                          child: Text('$minute ${AppStrings.focusMinuteUnit}'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: snapshot.phase == FocusPhase.idle
                      ? (int? value) {
                          if (value == null) {
                            return;
                          }
                          controller.setFocusDuration(value * 60);
                        }
                      : null,
                ),
              ],
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    _phaseLabel(snapshot.phase),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Text(
                      _formatSeconds(displaySeconds),
                      key: ValueKey<int>(displaySeconds),
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (snapshot.phase == FocusPhase.idle)
                FilledButton(
                  onPressed: controller.start,
                  child: const Text(AppStrings.focusStart),
                ),
              if (snapshot.isRunning)
                FilledButton.tonal(
                  onPressed: controller.pause,
                  child: const Text(AppStrings.focusPause),
                ),
              if (snapshot.isPaused)
                FilledButton.tonal(
                  onPressed: controller.resume,
                  child: const Text(AppStrings.focusResume),
                ),
              if (snapshot.phase != FocusPhase.idle)
                OutlinedButton(
                  onPressed: controller.stop,
                  child: const Text(AppStrings.focusStop),
                ),
              if (snapshot.phase == FocusPhase.breakTime)
                TextButton(
                  onPressed: controller.skipBreak,
                  child: const Text(AppStrings.focusSkipBreak),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                controller.triggerNotificationSelfCheck();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(AppStrings.focusSelfCheckQueued),
                  ),
                );
              },
              child: const Text(AppStrings.focusNotificationSelfCheck),
            ),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 8),
            Text(
              '${AppStrings.focusErrorPrefix}${state.error}',
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ],
      ),
    );
  }

  int _displaySeconds(FocusTimerSnapshot snapshot, int nowMs) {
    return switch (snapshot.phase) {
      FocusPhase.idle =>
        snapshot.mode == FocusMode.countdown
            ? snapshot.focusDurationSeconds
            : 0,
      FocusPhase.focus =>
        snapshot.mode == FocusMode.countdown
            ? snapshot.remainingAt(nowMs)
            : snapshot.elapsedAt(nowMs),
      FocusPhase.breakTime => snapshot.remainingAt(nowMs),
    };
  }

  String _phaseLabel(FocusPhase phase) {
    return switch (phase) {
      FocusPhase.idle => AppStrings.focusPhaseIdle,
      FocusPhase.focus => AppStrings.focusPhaseFocus,
      FocusPhase.breakTime => AppStrings.focusPhaseBreak,
    };
  }

  String _formatSeconds(int totalSeconds) {
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}
