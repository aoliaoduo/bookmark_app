import 'dart:math' as math;

enum FocusMode { countdown, countup }

enum FocusPhase { idle, focus, breakTime }

extension FocusModeDbCodec on FocusMode {
  String get dbValue {
    return switch (this) {
      FocusMode.countdown => 'countdown',
      FocusMode.countup => 'countup',
    };
  }

  static FocusMode fromDb(String value) {
    return switch (value) {
      'countup' => FocusMode.countup,
      _ => FocusMode.countdown,
    };
  }
}

extension FocusPhaseDbCodec on FocusPhase {
  String get dbValue {
    return switch (this) {
      FocusPhase.idle => 'idle',
      FocusPhase.focus => 'focus',
      FocusPhase.breakTime => 'break',
    };
  }

  static FocusPhase fromDb(String value) {
    return switch (value) {
      'focus' => FocusPhase.focus,
      'break' => FocusPhase.breakTime,
      _ => FocusPhase.idle,
    };
  }
}

class FocusTimerSnapshot {
  const FocusTimerSnapshot({
    required this.mode,
    required this.phase,
    required this.focusDurationSeconds,
    required this.startedAtMs,
    required this.durationSeconds,
    required this.elapsedSeconds,
    required this.focusRatioNum,
    required this.focusRatioDen,
    required this.updatedAtMs,
  });

  static const int defaultFocusDurationSeconds = 25 * 60;
  static const int minBreakSeconds = 60;

  final FocusMode mode;
  final FocusPhase phase;
  final int focusDurationSeconds;
  final int? startedAtMs;
  final int? durationSeconds;
  final int elapsedSeconds;
  final int focusRatioNum;
  final int focusRatioDen;
  final int updatedAtMs;

  factory FocusTimerSnapshot.idle({int nowMs = 0}) {
    return FocusTimerSnapshot(
      mode: FocusMode.countdown,
      phase: FocusPhase.idle,
      focusDurationSeconds: defaultFocusDurationSeconds,
      startedAtMs: null,
      durationSeconds: null,
      elapsedSeconds: 0,
      focusRatioNum: 5,
      focusRatioDen: 1,
      updatedAtMs: nowMs,
    );
  }

  bool get isRunning => phase != FocusPhase.idle && startedAtMs != null;

  bool get isPaused => phase != FocusPhase.idle && startedAtMs == null;

  int elapsedAt(int nowMs) {
    if (!isRunning || startedAtMs == null) {
      return elapsedSeconds;
    }
    final int deltaSeconds = ((nowMs - startedAtMs!) ~/ 1000).clamp(0, 1 << 30);
    return elapsedSeconds + deltaSeconds;
  }

  int remainingAt(int nowMs) {
    if (durationSeconds == null) {
      return 0;
    }
    final int remaining = durationSeconds! - elapsedAt(nowMs);
    return math.max(0, remaining);
  }

  int breakSecondsForFocusElapsed(int focusElapsedSeconds) {
    final int ratioBreak =
        (focusElapsedSeconds * focusRatioDen) ~/ focusRatioNum;
    return math.max(minBreakSeconds, ratioBreak);
  }

  FocusTimerSnapshot copyWith({
    FocusMode? mode,
    FocusPhase? phase,
    int? focusDurationSeconds,
    int? startedAtMs,
    bool clearStartedAtMs = false,
    int? durationSeconds,
    bool clearDurationSeconds = false,
    int? elapsedSeconds,
    int? focusRatioNum,
    int? focusRatioDen,
    int? updatedAtMs,
  }) {
    return FocusTimerSnapshot(
      mode: mode ?? this.mode,
      phase: phase ?? this.phase,
      focusDurationSeconds: focusDurationSeconds ?? this.focusDurationSeconds,
      startedAtMs: clearStartedAtMs ? null : (startedAtMs ?? this.startedAtMs),
      durationSeconds: clearDurationSeconds
          ? null
          : (durationSeconds ?? this.durationSeconds),
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      focusRatioNum: focusRatioNum ?? this.focusRatioNum,
      focusRatioDen: focusRatioDen ?? this.focusRatioDen,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is FocusTimerSnapshot &&
        mode == other.mode &&
        phase == other.phase &&
        focusDurationSeconds == other.focusDurationSeconds &&
        startedAtMs == other.startedAtMs &&
        durationSeconds == other.durationSeconds &&
        elapsedSeconds == other.elapsedSeconds &&
        focusRatioNum == other.focusRatioNum &&
        focusRatioDen == other.focusRatioDen &&
        updatedAtMs == other.updatedAtMs;
  }

  @override
  int get hashCode => Object.hash(
    mode,
    phase,
    focusDurationSeconds,
    startedAtMs,
    durationSeconds,
    elapsedSeconds,
    focusRatioNum,
    focusRatioDen,
    updatedAtMs,
  );
}

class FocusTimerMachine {
  const FocusTimerMachine._();

  static FocusTimerSnapshot setMode(
    FocusTimerSnapshot current, {
    required FocusMode mode,
    required int nowMs,
  }) {
    if (current.phase != FocusPhase.idle || current.mode == mode) {
      return current;
    }
    return current.copyWith(mode: mode, updatedAtMs: nowMs);
  }

  static FocusTimerSnapshot setFocusDuration(
    FocusTimerSnapshot current, {
    required int focusDurationSeconds,
    required int nowMs,
  }) {
    if (focusDurationSeconds <= 0 || current.phase != FocusPhase.idle) {
      return current;
    }
    if (current.focusDurationSeconds == focusDurationSeconds) {
      return current;
    }
    return current.copyWith(
      focusDurationSeconds: focusDurationSeconds,
      updatedAtMs: nowMs,
    );
  }

  static FocusTimerSnapshot start(
    FocusTimerSnapshot current, {
    required int nowMs,
  }) {
    if (current.phase != FocusPhase.idle) {
      return current;
    }
    return _startFocus(
      current,
      startedAtMs: nowMs,
      elapsedSeconds: 0,
      nowMs: nowMs,
    );
  }

  static FocusTimerSnapshot pause(
    FocusTimerSnapshot current, {
    required int nowMs,
  }) {
    if (!current.isRunning) {
      return current;
    }
    return current.copyWith(
      clearStartedAtMs: true,
      elapsedSeconds: current.elapsedAt(nowMs),
      updatedAtMs: nowMs,
    );
  }

  static FocusTimerSnapshot resume(
    FocusTimerSnapshot current, {
    required int nowMs,
  }) {
    if (!current.isPaused) {
      return current;
    }
    return current.copyWith(startedAtMs: nowMs, updatedAtMs: nowMs);
  }

  static FocusTimerSnapshot stop(
    FocusTimerSnapshot current, {
    required int nowMs,
  }) {
    if (current.phase == FocusPhase.idle) {
      return current;
    }
    if (current.phase == FocusPhase.breakTime) {
      return _toIdle(current, nowMs: nowMs);
    }

    final int focusElapsedSeconds = current.elapsedAt(nowMs);
    if (focusElapsedSeconds <= 0) {
      return _toIdle(current, nowMs: nowMs);
    }
    return _toBreak(
      current,
      focusElapsedSeconds: focusElapsedSeconds,
      startedAtMs: nowMs,
      elapsedSeconds: 0,
      nowMs: nowMs,
    );
  }

  static FocusTimerSnapshot skipBreak(
    FocusTimerSnapshot current, {
    required int nowMs,
  }) {
    if (current.phase != FocusPhase.breakTime) {
      return current;
    }
    return _startFocus(
      current,
      startedAtMs: nowMs,
      elapsedSeconds: 0,
      nowMs: nowMs,
    );
  }

  static FocusTimerSnapshot reconcile(
    FocusTimerSnapshot current, {
    required int nowMs,
  }) {
    if (!current.isRunning) {
      return current;
    }

    FocusTimerSnapshot state = current;
    for (int i = 0; i < 8; i++) {
      if (state.phase == FocusPhase.focus &&
          state.mode == FocusMode.countdown) {
        final int focusDuration =
            state.durationSeconds ?? state.focusDurationSeconds;
        final int elapsed = state.elapsedAt(nowMs);
        if (elapsed < focusDuration) {
          return state;
        }
        final int overrunSeconds = elapsed - focusDuration;
        state = _toBreak(
          state,
          focusElapsedSeconds: focusDuration,
          startedAtMs: nowMs - overrunSeconds * 1000,
          elapsedSeconds: 0,
          nowMs: nowMs,
        );
        continue;
      }

      if (state.phase == FocusPhase.breakTime) {
        final int breakDuration = state.durationSeconds ?? 0;
        final int elapsed = state.elapsedAt(nowMs);
        if (elapsed < breakDuration) {
          return state;
        }
        final int overrunSeconds = elapsed - breakDuration;
        state = _startFocus(
          state,
          startedAtMs: nowMs - overrunSeconds * 1000,
          elapsedSeconds: 0,
          nowMs: nowMs,
        );
        continue;
      }

      return state;
    }

    return state;
  }

  static FocusTimerSnapshot _startFocus(
    FocusTimerSnapshot current, {
    required int startedAtMs,
    required int elapsedSeconds,
    required int nowMs,
  }) {
    return current.copyWith(
      phase: FocusPhase.focus,
      startedAtMs: startedAtMs,
      durationSeconds: current.mode == FocusMode.countdown
          ? current.focusDurationSeconds
          : null,
      clearDurationSeconds: current.mode == FocusMode.countup,
      elapsedSeconds: elapsedSeconds,
      updatedAtMs: nowMs,
    );
  }

  static FocusTimerSnapshot _toBreak(
    FocusTimerSnapshot current, {
    required int focusElapsedSeconds,
    required int startedAtMs,
    required int elapsedSeconds,
    required int nowMs,
  }) {
    return current.copyWith(
      phase: FocusPhase.breakTime,
      startedAtMs: startedAtMs,
      durationSeconds: current.breakSecondsForFocusElapsed(focusElapsedSeconds),
      elapsedSeconds: elapsedSeconds,
      updatedAtMs: nowMs,
    );
  }

  static FocusTimerSnapshot _toIdle(
    FocusTimerSnapshot current, {
    required int nowMs,
  }) {
    return current.copyWith(
      phase: FocusPhase.idle,
      clearStartedAtMs: true,
      clearDurationSeconds: true,
      elapsedSeconds: 0,
      updatedAtMs: nowMs,
    );
  }
}
