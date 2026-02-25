import 'package:file_picker/file_picker.dart';

abstract class FileDialogAdapter {
  Future<String?> saveFile({
    required String dialogTitle,
    required String fileName,
  });

  Future<String?> pickDirectory({
    required String dialogTitle,
  });
}

class FilePickerDialogAdapter implements FileDialogAdapter {
  const FilePickerDialogAdapter();

  @override
  Future<String?> saveFile({
    required String dialogTitle,
    required String fileName,
  }) {
    return FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
    );
  }

  @override
  Future<String?> pickDirectory({
    required String dialogTitle,
  }) {
    return FilePicker.platform.getDirectoryPath(dialogTitle: dialogTitle);
  }
}
