import 'dart:async';

import 'package:flutter_riverpod/legacy.dart';

import '../../core/clock/app_clock.dart';
import '../../core/focus/focus_timer.dart';
import 'data/focus_state_repository.dart';
import 'notifications/focus_notification_scheduler.dart';

class FocusControllerState {
  const FocusControllerState({
    required this.initialized,
    required this.snapshot,
    required this.nowMs,
    this.error,
  });

  factory FocusControllerState.loading() {
    return FocusControllerState(
      initialized: false,
      snapshot: FocusTimerSnapshot.idle(),
      nowMs: 0,
    );
  }

  final bool initialized;
  final FocusTimerSnapshot snapshot;
  final int nowMs;
  final String? error;

  FocusControllerState copyWith({
    bool? initialized,
    FocusTimerSnapshot? snapshot,
    int? nowMs,
    String? error,
    bool clearError = false,
  }) {
    return FocusControllerState(
      initialized: initialized ?? this.initialized,
      snapshot: snapshot ?? this.snapshot,
      nowMs: nowMs ?? this.nowMs,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class FocusController extends StateNotifier<FocusControllerState> {
  FocusController({
    required this.repository,
    required this.clock,
    required this.notificationScheduler,
  }) : super(FocusControllerState.loading()) {
    unawaited(_bootstrap());
  }

  final FocusStateRepository repository;
  final AppClock clock;
  final FocusNotificationScheduler notificationScheduler;

  Timer? _ticker;
  bool _tickInFlight = false;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> setMode(FocusMode mode) async {
    await _applyTransition(
      (FocusTimerSnapshot current, int nowMs) =>
          FocusTimerMachine.setMode(current, mode: mode, nowMs: nowMs),
    );
  }

  Future<void> setFocusDuration(int focusDurationSeconds) async {
    await _applyTransition(
      (FocusTimerSnapshot current, int nowMs) =>
          FocusTimerMachine.setFocusDuration(
            current,
            focusDurationSeconds: focusDurationSeconds,
            nowMs: nowMs,
          ),
    );
  }

  Future<void> start() async {
    await _applyTransition(
      (FocusTimerSnapshot current, int nowMs) =>
          FocusTimerMachine.start(current, nowMs: nowMs),
    );
  }

  Future<void> pause() async {
    await _applyTransition(
      (FocusTimerSnapshot current, int nowMs) =>
          FocusTimerMachine.pause(current, nowMs: nowMs),
    );
  }

  Future<void> resume() async {
    await _applyTransition(
      (FocusTimerSnapshot current, int nowMs) =>
          FocusTimerMachine.resume(current, nowMs: nowMs),
    );
  }

  Future<void> stop() async {
    await _applyTransition(
      (FocusTimerSnapshot current, int nowMs) =>
          FocusTimerMachine.stop(current, nowMs: nowMs),
    );
  }

  Future<void> skipBreak() async {
    await _applyTransition(
      (FocusTimerSnapshot current, int nowMs) =>
          FocusTimerMachine.skipBreak(current, nowMs: nowMs),
    );
  }

  Future<void> triggerNotificationSelfCheck() async {
    await notificationScheduler.scheduleSelfCheck(afterSeconds: 10);
  }

  Future<void> _bootstrap() async {
    final int nowMs = clock.nowMs();
    try {
      await notificationScheduler.initialize();
      final FocusTimerSnapshot saved =
          await repository.load() ?? FocusTimerSnapshot.idle(nowMs: nowMs);
      final FocusTimerSnapshot restored = FocusTimerMachine.reconcile(
        saved,
        nowMs: nowMs,
      );
      state = state.copyWith(
        initialized: true,
        snapshot: restored,
        nowMs: nowMs,
        clearError: true,
      );
      await repository.save(restored);
      await notificationScheduler.scheduleForState(restored, nowMs: nowMs);
      _syncTicker();
    } catch (error) {
      state = state.copyWith(
        initialized: true,
        nowMs: nowMs,
        error: error.toString(),
      );
    }
  }

  Future<void> _applyTransition(
    FocusTimerSnapshot Function(FocusTimerSnapshot current, int nowMs) mutate,
  ) async {
    if (!state.initialized) {
      return;
    }
    final int nowMs = clock.nowMs();
    final FocusTimerSnapshot current = state.snapshot;
    final FocusTimerSnapshot next = mutate(current, nowMs);

    if (next == current) {
      state = state.copyWith(nowMs: nowMs);
      return;
    }

    state = state.copyWith(snapshot: next, nowMs: nowMs, clearError: true);
    await repository.save(next);
    await notificationScheduler.scheduleForState(next, nowMs: nowMs);
    _syncTicker();
  }

  void _syncTicker() {
    if (!state.snapshot.isRunning) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_onTick());
    });
  }

  Future<void> _onTick() async {
    if (_tickInFlight || !state.initialized) {
      return;
    }
    _tickInFlight = true;
    try {
      final int nowMs = clock.nowMs();
      final FocusTimerSnapshot current = state.snapshot;
      final FocusTimerSnapshot reconciled = FocusTimerMachine.reconcile(
        current,
        nowMs: nowMs,
      );

      if (reconciled == current) {
        state = state.copyWith(nowMs: nowMs);
        return;
      }

      state = state.copyWith(
        snapshot: reconciled,
        nowMs: nowMs,
        clearError: true,
      );
      await repository.save(reconciled);
      await notificationScheduler.scheduleForState(reconciled, nowMs: nowMs);
      _syncTicker();
    } finally {
      _tickInFlight = false;
    }
  }
}
