import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/shortcut/accelerator.dart';

void main() {
  group('parsing and formatting', () {
    test('reads the spelling GNOME stores', () {
      final accelerator = Accelerator.tryParse('<Control><Super>t')!;

      expect(accelerator.modifiers, {
        AcceleratorModifier.control,
        AcceleratorModifier.superKey,
      });
      expect(accelerator.key, 't');
      expect(accelerator.toGtk(), '<Control><Super>t');
      expect(accelerator.label, 'Ctrl+Super+T');
    });

    test('is the same shortcut whatever the order or spelling', () {
      expect(
        Accelerator.tryParse('<Super><Primary>T'),
        Accelerator.tryParse('<Control><Super>t'),
      );
      expect(
        Accelerator.tryParse('<Mod1><Shift>F5'),
        Accelerator.tryParse('<Shift><Alt>F5'),
      );
      expect(
        Accelerator.tryParse('<Super>a'),
        isNot(Accelerator.tryParse('<Super><Shift>a')),
      );
    });

    test('keeps function and named keys readable', () {
      expect(Accelerator.tryParse('<Alt>F4')!.label, 'Alt+F4');
      expect(Accelerator.tryParse('<Super>space')!.label, 'Super+Space');
      expect(Accelerator.tryParse('<Control>Print')!.label, 'Ctrl+Print');
    });

    test('rejects text that is not a shortcut', () {
      expect(Accelerator.tryParse(''), isNull);
      expect(Accelerator.tryParse('<Bogus>t'), isNull);
      expect(Accelerator.tryParse('<Control>'), isNull);
      expect(Accelerator.tryParse('two words'), isNull);
    });
  });

  group('usable as a global shortcut', () {
    test('needs Ctrl, Alt or Super, or a function key', () {
      expect(Accelerator.tryParse('<Control>t')!.isUsableGlobally, isTrue);
      expect(Accelerator.tryParse('<Super>t')!.isUsableGlobally, isTrue);
      expect(Accelerator.tryParse('F9')!.isUsableGlobally, isTrue);
      expect(Accelerator.tryParse('t')!.isUsableGlobally, isFalse);
      expect(Accelerator.tryParse('<Shift>t')!.isUsableGlobally, isFalse);
    });
  });

  group('from a key press', () {
    test('names letters, digits, and special keys', () {
      Accelerator? press(
        LogicalKeyboardKey key, {
        bool control = false,
        bool alt = false,
        bool shift = false,
        bool superKey = false,
      }) => acceleratorFromKey(
        key,
        control: control,
        alt: alt,
        shift: shift,
        superKey: superKey,
      );

      expect(
        press(LogicalKeyboardKey.keyK, control: true, alt: true)!.toGtk(),
        '<Control><Alt>k',
      );
      expect(
        press(LogicalKeyboardKey.digit5, superKey: true)!.toGtk(),
        '<Super>5',
      );
      expect(
        press(LogicalKeyboardKey.f8, control: true)!.toGtk(),
        '<Control>F8',
      );
      expect(
        press(LogicalKeyboardKey.space, superKey: true)!.toGtk(),
        '<Super>space',
      );
    });

    test('ignores modifiers pressed alone and keys with no name', () {
      expect(
        acceleratorFromKey(
          LogicalKeyboardKey.controlLeft,
          control: true,
          alt: false,
          shift: false,
          superKey: false,
        ),
        isNull,
      );
      expect(
        acceleratorFromKey(
          LogicalKeyboardKey.audioVolumeUp,
          control: true,
          alt: false,
          shift: false,
          superKey: false,
        ),
        isNull,
      );
    });
  });
}
