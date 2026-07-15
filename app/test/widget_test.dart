import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ubuntu_live_text/ui/live_text_app.dart';

void main() {
  testWidgets('shows Live Text empty state', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: LiveTextApp()));
    await tester.pumpAndSettle();

    expect(find.text('Live Text'), findsOneWidget);
    expect(find.text('Open image'), findsOneWidget);
  });
}
