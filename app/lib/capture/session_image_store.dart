import 'dart:io';
import 'dart:typed_data';

/// A screen capture copied into app-private storage for one capture session.
class SessionImage {
  SessionImage._(this.path);

  final String path;
  bool _discarded = false;

  Future<void> discard() async {
    if (_discarded) {
      return;
    }
    _discarded = true;
    try {
      await File(path).delete();
    } on FileSystemException {
      // Already gone; nothing else is ever deleted.
    }
  }
}

/// Owns silent-capture files. A silent capture lands in `~/Pictures`; the app
/// reads it, deletes exactly that returned path, and keeps a 0600 private copy
/// in a 0700 directory under `$XDG_RUNTIME_DIR` because OCR and the workspace
/// read images by path.
class SessionImageStore {
  SessionImageStore({this._root});

  final Directory? _root;
  Future<Directory>? _directory;
  int _counter = 0;

  /// Moves the portal's file into private storage. Throws
  /// [FileSystemException] when [returnedPath] is not a readable regular file.
  Future<SessionImage> adopt(String returnedPath) async =>
      write(await take(returnedPath));

  /// Reads the portal's file into memory and deletes exactly that path.
  /// Throws [FileSystemException] when [returnedPath] is not a readable
  /// regular file.
  Future<Uint8List> take(String returnedPath) async {
    final bytes = await _readRegularFile(returnedPath);
    await deleteReturned(returnedPath);
    return bytes;
  }

  /// Writes an encoded image into private storage for this session.
  Future<SessionImage> write(List<int> bytes) async {
    final directory = await (_directory ??= _createDirectory());
    final file = File('${directory.path}/screen-capture-${++_counter}.png');
    await file.create(exclusive: true);
    await _restrictToOwner(file.path);
    await file.writeAsBytes(bytes, flush: true);
    return SessionImage._(file.path);
  }

  /// Deletes a portal-returned capture the app no longer needs. Only a regular
  /// file at exactly [returnedPath] is removed.
  Future<void> deleteReturned(String returnedPath) async {
    if (await FileSystemEntity.type(returnedPath, followLinks: false) !=
        FileSystemEntityType.file) {
      return;
    }
    try {
      await File(returnedPath).delete();
    } on FileSystemException {
      // Raced with another deletion; the file is gone either way.
    }
  }

  /// Removes the private directory and any session image still inside it.
  void dispose() {
    final directory = _directory;
    _directory = null;
    directory?.then((dir) {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // The runtime directory is cleared at logout anyway.
      }
    }, onError: (Object _) {});
  }

  Future<Uint8List> _readRegularFile(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException('not a regular file', path);
    }
    return File(path).readAsBytes();
  }

  Future<Directory> _createDirectory() async {
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    final parent =
        _root ??
        (runtime != null && runtime.isNotEmpty
            ? Directory(runtime)
            : Directory.systemTemp);
    final directory = await parent.createTemp('kiriglyph-');
    await _restrictToOwner(directory.path, mode: '700');
    return directory;
  }

  Future<void> _restrictToOwner(String path, {String mode = '600'}) async {
    try {
      await Process.run('chmod', [mode, path]);
    } on ProcessException {
      // `$XDG_RUNTIME_DIR` is itself 0700, which keeps its contents private.
    }
  }
}
