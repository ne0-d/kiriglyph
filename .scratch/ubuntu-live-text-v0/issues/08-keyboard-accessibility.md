# 08: Make the complete flow keyboard and accessibility operable

**What to build:** A keyboard or assistive-technology user can complete image and portal capture workflows, navigate recognized text, copy a selection, understand status, and return focus without relying on painted regions alone.

**Blocked by:** 05: Validate and enable word selection; 06: Capture visible content through GNOME.

**Status:** ready-for-agent

- [ ] Tab and Shift+Tab follow a logical focus order and every pointer action has a keyboard path.
- [ ] Arrow keys move through text regions, Shift+arrows extend selection, Enter copies, Ctrl+A selects all, Ctrl+C copies, and Escape dismisses.
- [ ] The synchronized text representation exposes ordered recognized content through standard Flutter semantics.
- [ ] Progress, copied, no-text, cancelled, and failure states have concise accessible announcements that do not speak recognized content automatically.
- [ ] Closing or cancelling restores focus to a predictable application control.
- [ ] Manual acceptance covers Orca, keyboard-only use, large text, light/dark themes, and high contrast on Ubuntu Wayland.
