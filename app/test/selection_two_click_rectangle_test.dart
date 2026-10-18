import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/selection/rectangle_selection.dart';

void main() {
  group('TwoClickRectangleSession', () {
    test('first click stores the corner without finishing', () {
      const session = TwoClickRectangleSession();
      const first = SelectionPoint(10, 20);

      final outcome = session.applyClick(first);

      expect(outcome.selection, isNull);
      expect(outcome.session.firstCorner, first);
      expect(outcome.session.awaitingSecondClick, isTrue);
    });

    test('second click builds the same rectangle as a drag', () {
      const session = TwoClickRectangleSession(
        firstCorner: SelectionPoint(120, 90),
      );
      const second = SelectionPoint(40, 20);

      final outcome = session.applyClick(second);

      expect(
        outcome.selection!.rect,
        RectangleSelection.fromDrag(const SelectionPoint(120, 90), second).rect,
      );
      expect(outcome.session.awaitingSecondClick, isFalse);
    });

    test('preview tracks the pointer between clicks', () {
      const session = TwoClickRectangleSession(
        firstCorner: SelectionPoint(10, 10),
      );

      final preview = session.preview(const SelectionPoint(30, 40));

      expect(preview?.rect.left, 10);
      expect(preview?.rect.top, 10);
      expect(preview?.rect.right, 30);
      expect(preview?.rect.bottom, 40);
    });

    test('reset clears a pending first corner', () {
      const session = TwoClickRectangleSession(
        firstCorner: SelectionPoint(5, 5),
      );

      expect(session.reset().awaitingSecondClick, isFalse);
    });

    test('tool switch uses reset to drop a pending corner', () {
      const session = TwoClickRectangleSession(
        firstCorner: SelectionPoint(8, 9),
      );

      expect(session.reset().firstCorner, isNull);
    });
  });
}
