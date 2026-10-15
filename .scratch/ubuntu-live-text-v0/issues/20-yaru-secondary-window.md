# 20: Yaru theme and secondary window

**What to build:** The app uses Yaru for Ubuntu-native look, and the normal
window becomes the secondary surface for opening image files, onboarding, and
the one-time instant-capture permission.

**Blocked by:** 16: Prove silent capture and active-display placement

**Status:** resolved

- [x] The `yaru` package provides theme, controls, and icons, following the
  system light or dark preference.
- [x] The window offers Open image, Enable instant capture, and shortcut setup
  steps; the interactive Capture text picker button is removed.
- [x] Enable instant capture triggers GNOME's access dialog from the focused
  window and reports granted or denied, with steps to change it in Settings.
- [x] Existing workspace tests pass with the new theme.

Notes:

- Added `yaru` 11.0.0 after verifying it resolves with the vendored Flutter
  3.47.7 SDK.
- `flutter pub get` can generate Linux plugin-registration changes for Yaru's
  GTK/settings support; those files are outside this issue's allowed paths and
  should be handled with the native/app-linux work.
- The visible window now calls `instantCaptureProvider.requestPermission()` and
  reports mocked granted, denied, unavailable, and failed outcomes; the provider
  remains unwired until the capture owner completes the real portal integration.
- `flutter test` passes 134 tests and `flutter analyze` reports no issues.

**Note:** the Open image action and in-window workspace this ticket kept are
removed by 21. The setup window, theme, and permission flow remain.
