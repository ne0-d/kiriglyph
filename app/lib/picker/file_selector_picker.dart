import 'package:file_selector/file_selector.dart';

import 'package:ubuntu_live_text/picker/image_picker_port.dart';

class FileSelectorImagePicker implements ImagePickerPort {
  @override
  Future<String?> pickImagePath() async {
    const group = XTypeGroup(
      label: 'images',
      extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    return file?.path;
  }
}
