import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/web/link_opener.dart';
import 'package:kiriglyph/web/web_search_launcher.dart';

void main() {
  test(
    'link opener allows only http, https, mailto, and tel without a shell',
    () {
      expect(LinkOpener.buildOpenCommand('https://example.com'), [
        'xdg-open',
        ['https://example.com'],
      ]);
      expect(LinkOpener.buildOpenCommand('mailto:neo@example.dev'), [
        'xdg-open',
        ['mailto:neo@example.dev'],
      ]);
      expect(
        () => LinkOpener.buildOpenCommand('javascript:alert(1)'),
        throwsA(isA<LinkOpenException>()),
      );
    },
  );

  test('web search uses Firefox search or xdg-open Google fallback', () {
    expect(
      WebSearchLauncher.buildSearchCommand(
        query: 'hello world',
        defaultBrowser: 'firefox.desktop',
      ),
      [
        'firefox',
        ['--search', 'hello world'],
      ],
    );
    expect(
      WebSearchLauncher.buildSearchCommand(
        query: 'hello world',
        defaultBrowser: 'chromium.desktop',
      ),
      [
        'xdg-open',
        ['https://www.google.com/search?q=hello+world'],
      ],
    );
  });

  test('web search caps long queries', () {
    final command = WebSearchLauncher.buildSearchCommand(
      query: 'x' * 600,
      defaultBrowser: 'chromium.desktop',
    );
    final url = (command[1] as List<String>).single;

    expect(url.length, lessThan(600));
  });
}
