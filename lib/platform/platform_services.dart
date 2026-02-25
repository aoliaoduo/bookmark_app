import 'file_dialog_adapter.dart';
import 'platform_adapter.dart';

class PlatformServices {
  PlatformServices({
    PlatformAdapter? platformAdapter,
    FileDialogAdapter? fileDialogAdapter,
  })  : platform = platformAdapter ?? const FlutterPlatformAdapter(),
        fileDialog = fileDialogAdapter ?? const FilePickerDialogAdapter();

  final PlatformAdapter platform;
  final FileDialogAdapter fileDialog;

  static PlatformServices instance = PlatformServices();

  static void configureForTest(PlatformServices services) {
    instance = services;
  }

  static void resetToDefault() {
    instance = PlatformServices();
  }
}
