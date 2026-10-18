import 'dart:io';

typedef SearchCommand = List<Object>;

const int webSearchQueryMaxLength = 256;

class WebSearchLauncher {
  const WebSearchLauncher({
    this.processRun = Process.run,
    this.processStart = Process.start,
  });

  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments,
  )
  processRun;
  final Future<Process> Function(String executable, List<String> arguments)
  processStart;

  static SearchCommand buildSearchCommand({
    required String query,
    required String defaultBrowser,
  }) {
    final capped = _capQuery(query);
    if (defaultBrowser.toLowerCase().contains('firefox')) {
      return [
        'firefox',
        ['--search', capped],
      ];
    }
    return [
      'xdg-open',
      ['https://www.google.com/search?q=${Uri.encodeQueryComponent(capped)}'],
    ];
  }

  Future<void> search(String query) async {
    final browser = await processRun('xdg-settings', [
      'get',
      'default-web-browser',
    ]);
    final command = buildSearchCommand(
      query: query,
      defaultBrowser: '${browser.stdout}'.trim(),
    );
    await processStart(command[0] as String, command[1] as List<String>);
  }

  static String _capQuery(String query) {
    final trimmed = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.runes.length <= webSearchQueryMaxLength) {
      return trimmed;
    }
    return String.fromCharCodes(trimmed.runes.take(webSearchQueryMaxLength));
  }
}
