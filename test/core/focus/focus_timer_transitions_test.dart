import 'package:code/core/focus/focus_timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('countdown transitions focus -> break -> focus', () {
    FocusTimerSnapshot state = FocusTimerSnapshot.idle(
      nowMs: 0,
    ).copyWith(focusDurationSeconds: 25 * 60);
    state = FocusTimerMachine.start(state, nowMs: 0);

    final FocusTimerSnapshot afterFocus = FocusTimerMachine.reconcile(
      state,
      nowMs: 25 * 60 * 1000,
    );
    expect(afterFocus.phase, FocusPhase.breakTime);
    expect(afterFocus.durationSeconds, 5 * 60);

    final FocusTimerSnapshot afterBreak = FocusTimerMachine.reconcile(
      afterFocus,
      nowMs: 30 * 60 * 1000,
    );
    expect(afterBreak.phase, FocusPhase.focus);
    expect(afterBreak.mode, FocusMode.countdown);
    expect(afterBreak.durationSeconds, 25 * 60);
  });

  test('countup stop uses elapsed to create break', () {
    FocusTimerSnapshot state = FocusTimerSnapshot.idle(
      nowMs: 0,
    ).copyWith(mode: FocusMode.countup);
    state = FocusTimerMachine.start(state, nowMs: 0);

    final FocusTimerSnapshot stopped = FocusTimerMachine.stop(
      state,
      nowMs: 15 * 60 * 1000,
    );
    expect(stopped.phase, FocusPhase.breakTime);
    expect(stopped.durationSeconds, 180);
  });
}
