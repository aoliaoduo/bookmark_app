import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class PlatformCapabilities {
  const PlatformCapabilities({
    required this.isWeb,
    required this.isWindows,
    required this.isLinux,
    required this.isMacOS,
    required this.isAndroid,
    required this.isIOS,
  });

  final bool isWeb;
  final bool isWindows;
  final bool isLinux;
  final bool isMacOS;
  final bool isAndroid;
  final bool isIOS;

  bool get isDesktop => isWindows || isLinux || isMacOS;
}

abstract class PlatformAdapter {
  PlatformCapabilities get capabilities;
  Future<String> getApplicationSupportPath();
  String? preferredAppFontFamily();
}

class FlutterPlatformAdapter implements PlatformAdapter {
  const FlutterPlatformAdapter();

  @override
  PlatformCapabilities get capabilities {
    final TargetPlatform platform = defaultTargetPlatform;
    return PlatformCapabilities(
      isWeb: kIsWeb,
      isWindows: !kIsWeb && platform == TargetPlatform.windows,
      isLinux: !kIsWeb && platform == TargetPlatform.linux,
      isMacOS: !kIsWeb && platform == TargetPlatform.macOS,
      isAndroid: !kIsWeb && platform == TargetPlatform.android,
      isIOS: !kIsWeb && platform == TargetPlatform.iOS,
    );
  }

  @override
  Future<String> getApplicationSupportPath() async {
    final directory = await getApplicationSupportDirectory();
    return directory.path;
  }

  @override
  String? preferredAppFontFamily() {
    if (capabilities.isWindows) {
      return 'Microsoft YaHei';
    }
    return null;
  }
}
