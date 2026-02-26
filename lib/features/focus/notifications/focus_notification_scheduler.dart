import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';

import '../../../core/clock/app_clock.dart';
import '../../../core/focus/focus_timer.dart';

abstract interface class FocusNotificationScheduler {
  Future<void> initialize();

  Future<void> scheduleForState(
    FocusTimerSnapshot snapshot, {
    required int nowMs,
  });

  Future<void> cancelAll();

  Future<void> scheduleSelfCheck({int afterSeconds = 10});
}

abstract interface class FocusNotificationGateway {
  Future<void> initialize();

  Future<void> show({
    required int id,
    required String title,
    required String body,
  });

  Future<void> cancel(int id);

  Future<void> cancelAll();
}

class ShellFocusNotificationGateway implements FocusNotificationGateway {
  static final Logger _log = Logger('FocusNotificationGateway');
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    if (!Platform.isWindows) {
      _log.info('通知[$id] $title - $body');
      return;
    }

    final String safeTitle = _escapeXml(title);
    final String safeBody = _escapeXml(body);
    final String xml =
        "<toast><visual><binding template='ToastGeneric'>"
        '<text>$safeTitle</text><text>$safeBody</text>'
        '</binding></visual></toast>';
    final String script =
        '''
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime] | Out-Null
\$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
\$xml.LoadXml('${_escapeSingleQuote(xml)}')
\$toast = [Windows.UI.Notifications.ToastNotification]::new(\$xml)
\$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('PowerShell')
\$notifier.Show(\$toast)
''';
    try {
      await Process.run('powershell', <String>[
        '-NoProfile',
        '-Command',
        script,
      ]);
    } catch (error) {
      _log.warning('Windows toast 发送失败: $error');
    }
  }

  @override
  Future<void> cancel(int id) async {
    // Shell toast is fire-and-forget. No direct revoke support in this M4 layer.
  }

  @override
  Future<void> cancelAll() async {}

  String _escapeXml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  String _escapeSingleQuote(String value) {
    return value.replaceAll("'", "''");
  }
}

class TimerBasedFocusNotificationScheduler
    implements FocusNotificationScheduler {
  TimerBasedFocusNotificationScheduler({
    required this.clock,
    required this.gateway,
  });

  static const int focusEndNotificationId = 41001;
  static const int breakEndNotificationId = 41002;
  static const int selfCheckNotificationId = 41003;

  static final Logger _log = Logger('FocusNotificationScheduler');

  final AppClock clock;
  final FocusNotificationGateway gateway;

  Timer? _focusEndTimer;
  Timer? _breakEndTimer;
  Timer? _selfCheckTimer;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await gateway.initialize();
    _initialized = true;
  }

  @override
  Future<void> scheduleForState(
    FocusTimerSnapshot snapshot, {
    required int nowMs,
  }) async {
    await initialize();

    if (snapshot.phase == FocusPhase.idle || snapshot.isPaused) {
      await _cancelPhaseSchedules();
      return;
    }

    if (snapshot.phase == FocusPhase.focus &&
        snapshot.mode == FocusMode.countdown) {
      final int remainingSeconds = snapshot.remainingAt(nowMs);
      await _scheduleFocusEnd(remainingSeconds);
      _cancelTimer(_breakEndTimer);
      _breakEndTimer = null;
      await gateway.cancel(breakEndNotificationId);
      return;
    }

    if (snapshot.phase == FocusPhase.breakTime) {
      final int remainingSeconds = snapshot.remainingAt(nowMs);
      await _scheduleBreakEnd(remainingSeconds);
      _cancelTimer(_focusEndTimer);
      _focusEndTimer = null;
      await gateway.cancel(focusEndNotificationId);
      return;
    }

    // Countup focus has no fixed end reminder by design.
    _cancelTimer(_focusEndTimer);
    _focusEndTimer = null;
    await gateway.cancel(focusEndNotificationId);
    _cancelTimer(_breakEndTimer);
    _breakEndTimer = null;
    await gateway.cancel(breakEndNotificationId);
  }

  @override
  Future<void> cancelAll() async {
    _cancelTimer(_focusEndTimer);
    _cancelTimer(_breakEndTimer);
    _cancelTimer(_selfCheckTimer);
    _focusEndTimer = null;
    _breakEndTimer = null;
    _selfCheckTimer = null;
    await gateway.cancelAll();
  }

  @override
  Future<void> scheduleSelfCheck({int afterSeconds = 10}) async {
    await initialize();
    _cancelTimer(_selfCheckTimer);
    await gateway.cancel(selfCheckNotificationId);
    _selfCheckTimer = Timer(Duration(seconds: afterSeconds), () {
      unawaited(
        gateway.show(
          id: selfCheckNotificationId,
          title: '专注提醒自检',
          body: '10 秒提醒触发成功',
        ),
      );
    });
  }

  Future<void> _scheduleFocusEnd(int afterSeconds) async {
    _cancelTimer(_focusEndTimer);
    await gateway.cancel(focusEndNotificationId);
    if (afterSeconds <= 0) {
      await gateway.show(
        id: focusEndNotificationId,
        title: '专注结束',
        body: '进入休息阶段',
      );
      return;
    }
    _focusEndTimer = Timer(Duration(seconds: afterSeconds), () {
      unawaited(
        gateway.show(id: focusEndNotificationId, title: '专注结束', body: '进入休息阶段'),
      );
    });
    _log.info('已安排专注结束通知：$afterSeconds 秒后');
  }

  Future<void> _scheduleBreakEnd(int afterSeconds) async {
    _cancelTimer(_breakEndTimer);
    await gateway.cancel(breakEndNotificationId);
    if (afterSeconds <= 0) {
      await gateway.show(
        id: breakEndNotificationId,
        title: '休息结束',
        body: '可以开始下一轮专注',
      );
      return;
    }
    _breakEndTimer = Timer(Duration(seconds: afterSeconds), () {
      unawaited(
        gateway.show(
          id: breakEndNotificationId,
          title: '休息结束',
          body: '可以开始下一轮专注',
        ),
      );
    });
    _log.info('已安排休息结束通知：$afterSeconds 秒后');
  }

  Future<void> _cancelPhaseSchedules() async {
    _cancelTimer(_focusEndTimer);
    _cancelTimer(_breakEndTimer);
    _focusEndTimer = null;
    _breakEndTimer = null;
    await gateway.cancel(focusEndNotificationId);
    await gateway.cancel(breakEndNotificationId);
  }

  void _cancelTimer(Timer? timer) {
    timer?.cancel();
  }
}

class AndroidAlarmManagerFocusNotificationScheduler
    implements FocusNotificationScheduler {
  AndroidAlarmManagerFocusNotificationScheduler({required this.fallback});

  static final Logger _log = Logger('AndroidAlarmManagerAdapter');
  bool _logged = false;
  final FocusNotificationScheduler fallback;

  @override
  Future<void> cancelAll() => fallback.cancelAll();

  @override
  Future<void> initialize() async {
    if (!_logged) {
      _log.info('AlarmManager 适配层已预留，当前使用进程内 fallback 调度');
      _logged = true;
    }
    await fallback.initialize();
  }

  @override
  Future<void> scheduleForState(
    FocusTimerSnapshot snapshot, {
    required int nowMs,
  }) async {
    await initialize();
    await fallback.scheduleForState(snapshot, nowMs: nowMs);
  }

  @override
  Future<void> scheduleSelfCheck({int afterSeconds = 10}) {
    return fallback.scheduleSelfCheck(afterSeconds: afterSeconds);
  }
}
