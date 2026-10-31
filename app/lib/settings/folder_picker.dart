import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks the user for a folder with the system's own chooser.
abstract interface class FolderPickerPort {
  /// The chosen folder, or null if the user cancelled.
  Future<String?> chooseFolder({String? current});
}

/// [FolderPickerPort] over the `kiriglyph/app` channel in `linux/runner`.
class PlatformFolderPicker implements FolderPickerPort {
  PlatformFolderPicker({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('kiriglyph/app');

  final MethodChannel _channel;

  @override
  Future<String?> chooseFolder({String? current}) async {
    try {
      final path = await _channel.invokeMethod<String>('chooseFolder', {
        'current': current,
      });
      return path == null || path.isEmpty ? null : path;
    } on MissingPluginException {
      return null;
    }
  }
}

final folderPickerProvider = Provider<FolderPickerPort>(
  (ref) => PlatformFolderPicker(),
);
