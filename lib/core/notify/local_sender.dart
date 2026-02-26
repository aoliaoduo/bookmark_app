import 'dart:io';

import 'package:logging/logging.dart';

class LocalSender {
  static final Logger _log = Logger('LocalSender');

  Future<void> send({required String title, required String message}) async {
    if (!Platform.isWindows) {
      _log.info('$title - $message');
      return;
    }

    final String safeTitle = _escapeXml(title);
    final String safeBody = _escapeXml(message);
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
    await Process.run('powershell', <String>['-NoProfile', '-Command', script]);
  }

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
