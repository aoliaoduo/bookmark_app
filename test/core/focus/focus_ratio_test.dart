import 'package:code/core/focus/focus_timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('15min focus maps to 180s break by 5:1 ratio', () {
    final FocusTimerSnapshot snapshot = FocusTimerSnapshot.idle(nowMs: 0);
    expect(snapshot.breakSecondsForFocusElapsed(15 * 60), 180);
  });

  test('1min focus still keeps break >= 60s', () {
    final FocusTimerSnapshot snapshot = FocusTimerSnapshot.idle(nowMs: 0);
    expect(snapshot.breakSecondsForFocusElapsed(60), 60);
  });
}
