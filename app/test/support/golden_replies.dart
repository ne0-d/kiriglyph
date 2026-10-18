import 'dart:io';

/// Repository root, walked upward from the running test file.
///
/// Flutter test sometimes reports [Platform.script] as a non-file URI.
/// In that case the walk starts at the process working directory, which
/// `scripts/check.sh` sets to `app/`.
Directory repoRoot() {
  final starts = <Directory>[];
  final script = Platform.script;
  if (script.scheme == 'file') {
    starts.add(File.fromUri(script).parent);
  }
  starts.add(Directory.current);
  for (final start in starts) {
    var dir = start;
    while (true) {
      final golden = Directory('${dir.path}/contracts/v1/golden');
      final app = Directory('${dir.path}/app');
      if (golden.existsSync() && app.existsSync()) {
        return dir;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) {
        break;
      }
      dir = parent;
    }
  }
  throw StateError('Could not resolve the repo root from ${Platform.script}');
}

/// Directory of checked-in worker NDJSON replies.
Directory get goldenDirectory =>
    Directory('${repoRoot().path}/contracts/v1/golden');

/// One golden reply, without the trailing newline.
String loadGoldenReply(String fileName) {
  final file = File('${goldenDirectory.path}/$fileName');
  final text = file.readAsStringSync().trimRight();
  if (text.isEmpty || text.contains('\n')) {
    throw StateError('$fileName must be one NDJSON line');
  }
  return text;
}

/// NDJSON file names in [goldenDirectory], sorted.
List<String> goldenNdjsonNames() {
  final names = goldenDirectory
      .listSync()
      .whereType<File>()
      .map((file) => file.uri.pathSegments.last)
      .where((name) => name.endsWith('.ndjson'))
      .toList();
  names.sort();
  return names;
}
