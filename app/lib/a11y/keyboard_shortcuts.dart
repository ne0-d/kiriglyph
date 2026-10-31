/// One documented key and what it does.
class ShortcutEntry {
  const ShortcutEntry(this.keys, this.action);

  final String keys;
  final String action;
}

class ShortcutGroup {
  const ShortcutGroup(this.title, this.entries);

  final String title;
  final List<ShortcutEntry> entries;
}

/// Every keyboard shortcut of the overlay, shown in the help panel. Each
/// entry has a widget test; keep both in step.
const keyboardShortcutGroups = <ShortcutGroup>[
  ShortcutGroup('Select text', [
    ShortcutEntry('Arrow keys', 'Move the selection over recognized text'),
    ShortcutEntry('Ctrl+Left / Ctrl+Right', 'Move by word'),
    ShortcutEntry('Home / End', 'Move to the start or end of the line'),
    ShortcutEntry('Ctrl+Shift+Up / Ctrl+Shift+Down', 'Select by paragraph'),
    ShortcutEntry('Shift with any of these', 'Extend the selection'),
    ShortcutEntry('Ctrl+A', 'Select all text'),
  ]),
  ShortcutGroup('Copy and save', [
    ShortcutEntry('Ctrl+C', 'Copy the selected text (or object image)'),
    ShortcutEntry('Ctrl+Shift+C', 'Copy the selection as an image'),
    ShortcutEntry('Ctrl+S', 'Save the main result to your save folder'),
    ShortcutEntry(
      'Ctrl+Shift+S',
      'Save as… for an object; screenshots save straight to your save folder',
    ),
    ShortcutEntry('Ctrl+Shift+F', 'Save a screenshot of the whole display'),
  ]),
  ShortcutGroup('Select an object', [
    ShortcutEntry('O / Shift+O', 'Go to the next or previous object area'),
    ShortcutEntry('Arrow keys', 'Fine-tune the object cursor (Shift: larger)'),
    ShortcutEntry('Enter', 'Select the object (Shift: add, Alt: leave out)'),
    ShortcutEntry('Ctrl+Z', 'Undo the last object point'),
    ShortcutEntry('Backspace / Delete', 'Remove the object selection'),
  ]),
  ShortcutGroup('Rectangle', [
    ShortcutEntry('R', 'Start a rectangle, or reset it to the whole display'),
    ShortcutEntry('Arrow keys', 'Resize the rectangle'),
    ShortcutEntry('Alt+Arrow keys', 'Move the rectangle'),
    ShortcutEntry('Ctrl with arrows', 'Move or resize by 1 pixel'),
    ShortcutEntry('Shift+Arrow keys', 'Snap the edge to the display edge'),
    ShortcutEntry('T', 'Cycle rectangle, two clicks, and free draw'),
  ]),
  ShortcutGroup('Overlay', [
    ShortcutEntry('F6', 'Move focus between the canvas and the toolbar'),
    ShortcutEntry('Tab / Shift+Tab', 'Next or previous control'),
    ShortcutEntry('Alt+Arrow keys', 'Move the toolbar (Shift: larger steps)'),
    ShortcutEntry('Escape', 'Step back: rectangle, then selection, then close'),
    ShortcutEntry('? / Ctrl+? / F1', 'Show or hide this help'),
  ]),
];

/// Pointer actions and their keyboard or click alternatives (WCAG 2.5.7).
const pointerAlternatives = <ShortcutEntry>[
  ShortcutEntry(
    'Drag a rectangle',
    'Use Two clicks in the toolbar, or press R and use the arrow keys',
  ),
  ShortcutEntry(
    'Draw a loop around an object',
    'Press O to pick an object area, or use a rectangle',
  ),
  ShortcutEntry('Drag text', 'Arrow keys, Shift+arrows, Ctrl+Shift+Up or Down'),
  ShortcutEntry(
    'Drag the toolbar',
    'Alt+arrow keys on the toolbar, or the Move toolbar menu',
  ),
];
