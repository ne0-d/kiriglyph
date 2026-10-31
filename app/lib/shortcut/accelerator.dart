import 'package:flutter/services.dart';

enum AcceleratorModifier { control, alt, shift, superKey }

/// A keyboard shortcut in the form GNOME stores it, such as
/// `<Control><Super>t`. Equal shortcuts compare equal whatever order the
/// modifiers were written in.
class Accelerator {
  Accelerator(Set<AcceleratorModifier> modifiers, String key)
    : modifiers = Set.unmodifiable(modifiers),
      key = _canonicalKey(key);

  final Set<AcceleratorModifier> modifiers;

  /// The key's GDK name: a lower-case letter or digit, or a name such as
  /// `F5`, `space`, or `Print`.
  final String key;

  static const _modifierNames = {
    'primary': AcceleratorModifier.control,
    'control': AcceleratorModifier.control,
    'ctrl': AcceleratorModifier.control,
    'alt': AcceleratorModifier.alt,
    'mod1': AcceleratorModifier.alt,
    'shift': AcceleratorModifier.shift,
    'super': AcceleratorModifier.superKey,
    'mod4': AcceleratorModifier.superKey,
    'meta': AcceleratorModifier.superKey,
    'hyper': AcceleratorModifier.superKey,
  };

  static final _pattern = RegExp(r'^((?:<[A-Za-z0-9]+>)*)([^\s<]\S*)$');
  static final _modifierToken = RegExp('<([A-Za-z0-9]+)>');

  /// Parses `<Super><Control>t`; null for anything that is not a shortcut.
  static Accelerator? tryParse(String text) {
    final match = _pattern.firstMatch(text.trim());
    if (match == null) {
      return null;
    }
    final modifiers = <AcceleratorModifier>{};
    for (final token in _modifierToken.allMatches(match.group(1)!)) {
      final modifier = _modifierNames[token.group(1)!.toLowerCase()];
      if (modifier == null) {
        return null;
      }
      modifiers.add(modifier);
    }
    return Accelerator(modifiers, match.group(2)!);
  }

  static String _canonicalKey(String key) =>
      key.length == 1 ? key.toLowerCase() : key;

  /// GNOME's own spelling, in a fixed modifier order.
  String toGtk() {
    final buffer = StringBuffer();
    if (modifiers.contains(AcceleratorModifier.control)) {
      buffer.write('<Control>');
    }
    if (modifiers.contains(AcceleratorModifier.alt)) {
      buffer.write('<Alt>');
    }
    if (modifiers.contains(AcceleratorModifier.shift)) {
      buffer.write('<Shift>');
    }
    if (modifiers.contains(AcceleratorModifier.superKey)) {
      buffer.write('<Super>');
    }
    buffer.write(key);
    return buffer.toString();
  }

  /// How people read it: `Ctrl+Super+T`.
  String get label {
    final parts = <String>[
      if (modifiers.contains(AcceleratorModifier.control)) 'Ctrl',
      if (modifiers.contains(AcceleratorModifier.alt)) 'Alt',
      if (modifiers.contains(AcceleratorModifier.shift)) 'Shift',
      if (modifiers.contains(AcceleratorModifier.superKey)) 'Super',
      key.length == 1 ? key.toUpperCase() : _friendlyKey(key),
    ];
    return parts.join('+');
  }

  /// Whether it is safe to grab globally: a bare letter, or Shift with a
  /// letter, would break typing in every app.
  bool get isUsableGlobally =>
      modifiers.any((modifier) => modifier != AcceleratorModifier.shift) ||
      RegExp(r'^F([1-9]|1[0-2])$').hasMatch(key);

  @override
  bool operator ==(Object other) =>
      other is Accelerator &&
      other.toGtk().toLowerCase() == toGtk().toLowerCase();

  @override
  int get hashCode => toGtk().toLowerCase().hashCode;

  @override
  String toString() => toGtk();
}

String _friendlyKey(String key) => switch (key) {
  'space' => 'Space',
  'Return' => 'Enter',
  'grave' => '`',
  'comma' => ',',
  'period' => '.',
  'slash' => '/',
  'minus' => '-',
  'equal' => '=',
  'semicolon' => ';',
  'apostrophe' => "'",
  'bracketleft' => '[',
  'bracketright' => ']',
  'backslash' => r'\',
  _ => key,
};

final _specialKeys = <LogicalKeyboardKey, String>{
  LogicalKeyboardKey.space: 'space',
  LogicalKeyboardKey.tab: 'Tab',
  LogicalKeyboardKey.enter: 'Return',
  LogicalKeyboardKey.arrowUp: 'Up',
  LogicalKeyboardKey.arrowDown: 'Down',
  LogicalKeyboardKey.arrowLeft: 'Left',
  LogicalKeyboardKey.arrowRight: 'Right',
  LogicalKeyboardKey.home: 'Home',
  LogicalKeyboardKey.end: 'End',
  LogicalKeyboardKey.pageUp: 'Page_Up',
  LogicalKeyboardKey.pageDown: 'Page_Down',
  LogicalKeyboardKey.printScreen: 'Print',
  LogicalKeyboardKey.backquote: 'grave',
  LogicalKeyboardKey.comma: 'comma',
  LogicalKeyboardKey.period: 'period',
  LogicalKeyboardKey.slash: 'slash',
  LogicalKeyboardKey.minus: 'minus',
  LogicalKeyboardKey.equal: 'equal',
  LogicalKeyboardKey.semicolon: 'semicolon',
  LogicalKeyboardKey.quote: 'apostrophe',
  LogicalKeyboardKey.bracketLeft: 'bracketleft',
  LogicalKeyboardKey.bracketRight: 'bracketright',
  LogicalKeyboardKey.backslash: 'backslash',
  LogicalKeyboardKey.f1: 'F1',
  LogicalKeyboardKey.f2: 'F2',
  LogicalKeyboardKey.f3: 'F3',
  LogicalKeyboardKey.f4: 'F4',
  LogicalKeyboardKey.f5: 'F5',
  LogicalKeyboardKey.f6: 'F6',
  LogicalKeyboardKey.f7: 'F7',
  LogicalKeyboardKey.f8: 'F8',
  LogicalKeyboardKey.f9: 'F9',
  LogicalKeyboardKey.f10: 'F10',
  LogicalKeyboardKey.f11: 'F11',
  LogicalKeyboardKey.f12: 'F12',
};

/// The shortcut a key press makes, or null while only modifiers are down or
/// the key has no shortcut name.
Accelerator? acceleratorFromKey(
  LogicalKeyboardKey key, {
  required bool control,
  required bool alt,
  required bool shift,
  required bool superKey,
}) {
  final special = _specialKeys[key];
  final label = key.keyLabel;
  final String? name;
  if (special != null) {
    name = special;
  } else if (label.length == 1 && RegExp('[A-Za-z0-9]').hasMatch(label)) {
    name = label.toLowerCase();
  } else {
    name = null;
  }
  if (name == null) {
    return null;
  }
  return Accelerator({
    if (control) AcceleratorModifier.control,
    if (alt) AcceleratorModifier.alt,
    if (shift) AcceleratorModifier.shift,
    if (superKey) AcceleratorModifier.superKey,
  }, name);
}
