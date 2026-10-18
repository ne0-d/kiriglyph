import 'dart:io';

const Set<String> linkOpenerAllowedSchemes = {'http', 'https', 'mailto', 'tel'};

typedef OpenCommand = List<Object>;

class LinkOpenException implements Exception {
  const LinkOpenException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LinkOpener {
  const LinkOpener({this.processStart = Process.start});

  final Future<Process> Function(String executable, List<String> arguments)
  processStart;

  static OpenCommand buildOpenCommand(String target) {
    final uri = Uri.tryParse(target);
    if (uri == null || !linkOpenerAllowedSchemes.contains(uri.scheme)) {
      throw const LinkOpenException('Link scheme is not allowed');
    }
    return [
      'xdg-open',
      [target],
    ];
  }

  Future<void> open(String target) async {
    final command = buildOpenCommand(target);
    await processStart(command[0] as String, command[1] as List<String>);
  }
}
