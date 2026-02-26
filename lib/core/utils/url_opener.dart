import 'dart:io';

class UrlOpener {
  const UrlOpener._();

  static Future<void> open(String url) async {
    if (url.trim().isEmpty) {
      throw Exception('URL 不能为空');
    }
    if (Platform.isWindows) {
      await Process.run('cmd', <String>['/c', 'start', '', url]);
      return;
    }
    if (Platform.isMacOS) {
      await Process.run('open', <String>[url]);
      return;
    }
    if (Platform.isLinux) {
      await Process.run('xdg-open', <String>[url]);
      return;
    }
    throw UnsupportedError('当前平台不支持打开外部链接');
  }
}
