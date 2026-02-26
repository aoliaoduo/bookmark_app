abstract class AppClock {
  int nowMs();
}

class SystemClock implements AppClock {
  @override
  int nowMs() => DateTime.now().millisecondsSinceEpoch;
}
