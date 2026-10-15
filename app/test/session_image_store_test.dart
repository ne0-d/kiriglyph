import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/capture/session_image_store.dart';

void main() {
  late Directory root;
  late Directory pictures;
  late Directory runtime;
  late SessionImageStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('session-image-store-');
    pictures = Directory('${root.path}/Pictures')..createSync();
    runtime = Directory('${root.path}/runtime')..createSync();
    store = SessionImageStore(root: runtime);
  });

  tearDown(() {
    store.dispose();
    root.deleteSync(recursive: true);
  });

  int mode(String path) => FileStat.statSync(path).mode & 0x1ff;

  test(
    'adopting moves exactly the returned file into private storage',
    () async {
      final returned = File('${pictures.path}/Screenshot.png')
        ..writeAsBytesSync([1, 2, 3]);
      final neighbour = File('${pictures.path}/Screenshot-1.png')
        ..writeAsBytesSync([9]);

      final image = await store.adopt(returned.path);

      expect(returned.existsSync(), isFalse);
      expect(neighbour.existsSync(), isTrue);
      expect(File(image.path).readAsBytesSync(), [1, 2, 3]);
      expect(image.path, startsWith(runtime.path));
      expect(mode(image.path), 0x180, reason: 'file is 0600');
      expect(mode(File(image.path).parent.path), 0x1c0, reason: 'dir is 0700');
    },
  );

  test(
    'taking reads the returned file into memory and stores nothing',
    () async {
      final returned = File('${pictures.path}/Screenshot.png')
        ..writeAsBytesSync([4, 5]);

      expect(await store.take(returned.path), [4, 5]);

      expect(returned.existsSync(), isFalse);
      expect(runtime.listSync(), isEmpty);
      final image = await store.write([6]);
      expect(File(image.path).readAsBytesSync(), [6]);
      expect(mode(image.path), 0x180, reason: 'file is 0600');
    },
  );

  test('discarding deletes only the private copy', () async {
    final returned = File('${pictures.path}/Screenshot.png')
      ..writeAsBytesSync([1]);
    final image = await store.adopt(returned.path);

    await image.discard();
    await image.discard();

    expect(File(image.path).existsSync(), isFalse);
    expect(pictures.listSync(), isEmpty);
  });

  test('a symlink is neither followed nor deleted', () async {
    final target = File('${root.path}/precious.png')..writeAsBytesSync([7]);
    final link = Link('${pictures.path}/Screenshot.png')
      ..createSync(target.path);

    await expectLater(
      store.adopt(link.path),
      throwsA(isA<FileSystemException>()),
    );
    await store.deleteReturned(link.path);

    expect(link.existsSync(), isTrue);
    expect(target.readAsBytesSync(), [7]);
  });

  test('dispose removes the private directory', () async {
    final returned = File('${pictures.path}/Screenshot.png')
      ..writeAsBytesSync([1]);
    final image = await store.adopt(returned.path);
    final directory = File(image.path).parent;

    store.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(directory.existsSync(), isFalse);
  });
}
