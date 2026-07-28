# 09: Make the Text flow keyboard and accessibility operable

**What to build:** A keyboard or assistive-technology user can complete image
and portal capture workflows, navigate exact text ranges, copy a selection,
understand status, and return focus without relying on painted geometry.

**Blocked by:** 06: Drag across exact text ranges; 07: Capture visible content
through GNOME.

**Status:** blocked

- [ ] Tab and Shift+Tab follow a logical focus order and every pointer action
  has a keyboard path.
- [ ] Arrow keys move through characters and lines, Shift+arrows extend
  selection, Enter copies, Ctrl+A selects all, Ctrl+C copies, and Escape
  dismisses.
- [ ] The synchronized text representation exposes ordered recognized content
  through standard Flutter semantics.
- [ ] Progress, copied, no-text, cancelled, and failure states have concise
  accessible announcements that do not speak recognized content automatically.
- [ ] Closing or cancelling restores focus to a predictable application
  control.
- [ ] Manual acceptance covers Orca, keyboard-only use, large text, light and
  dark themes, and high contrast on Ubuntu Wayland.
