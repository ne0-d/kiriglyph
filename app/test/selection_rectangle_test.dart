import 'package:flutter_test/flutter_test.dart';
import 'package:kiriglyph/selection/rectangle_selection.dart';

void main() {
  test('rectangle drag normalizes endpoints and enforces minimum size', () {
    final selection = RectangleSelection.fromDrag(
      const SelectionPoint(120, 90),
      const SelectionPoint(40, 20),
    );

    expect(selection.rect.left, 40);
    expect(selection.rect.top, 20);
    expect(selection.rect.right, 120);
    expect(selection.rect.bottom, 90);
  });

  test('keyboard arrows resize and Alt arrows move', () {
    const selection = RectangleSelection(
      SelectionRect(left: 10, top: 20, right: 60, bottom: 80),
    );

    expect(
      selection.applyKeyboard(RectangleKeyboardCommand.arrowRight).rect.right,
      70,
    );
    expect(
      selection
          .applyKeyboard(
            RectangleKeyboardCommand.arrowRight,
            modifiers: const RectangleKeyboardModifiers(alt: true),
          )
          .rect
          .left,
      20,
    );
    expect(
      selection
          .applyKeyboard(
            RectangleKeyboardCommand.arrowDown,
            modifiers: const RectangleKeyboardModifiers(control: true),
          )
          .rect
          .bottom,
      81,
    );
  });

  test(
    'Shift arrows snap to image edges and reset restores the image bounds',
    () {
      const selection = RectangleSelection(
        SelectionRect(left: 10, top: 20, right: 60, bottom: 80),
      );
      const bounds = SelectionRect(left: 0, top: 0, right: 100, bottom: 90);

      expect(
        selection
            .applyKeyboard(
              RectangleKeyboardCommand.arrowRight,
              modifiers: const RectangleKeyboardModifiers(shift: true),
              bounds: bounds,
            )
            .rect
            .right,
        100,
      );
      expect(selection.reset(bounds).rect, bounds);
    },
  );
}
