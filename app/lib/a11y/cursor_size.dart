import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// GNOME's default `cursor-size`; handles and the object cursor are designed
/// for it.
const defaultCursorSize = 24;

/// Largest scale applied, however big the system cursor is.
const maxCursorScale = 3.0;

/// Scale for handles and the object cursor from a GNOME cursor size.
///
/// Fails open to 1.0 for a missing or nonsensical value and never shrinks
/// below 1.0, so 24 px targets stay 24 px even with a small cursor.
double cursorScaleFor(int? cursorSize) {
  if (cursorSize == null || cursorSize <= 0) {
    return 1;
  }
  final scale = cursorSize / defaultCursorSize;
  if (scale.isNaN) {
    return 1;
  }
  return scale.clamp(1.0, maxCursorScale);
}

/// Reads `org.gnome.desktop.interface cursor-size` over the Settings portal.
abstract interface class GnomeCursorSizePort {
  Future<int?> readCursorSize();
}

class PortalGnomeCursorSizePort implements GnomeCursorSizePort {
  PortalGnomeCursorSizePort({DBusClient? client})
    : _client = client ?? DBusClient.session();

  final DBusClient _client;

  static const _destination = 'org.freedesktop.portal.Desktop';
  static final _path = DBusObjectPath('/org/freedesktop/portal/desktop');
  static const _interface = 'org.freedesktop.portal.Settings';
  static const _namespace = 'org.gnome.desktop.interface';
  static const _key = 'cursor-size';

  @override
  Future<int?> readCursorSize() async {
    if (kIsWeb) {
      return null;
    }
    final reply = await _client.callMethod(
      destination: _destination,
      path: _path,
      interface: _interface,
      name: 'Read',
      values: [const DBusString(_namespace), const DBusString(_key)],
    );
    final values = reply.returnValues;
    if (values.isEmpty) {
      return null;
    }
    var value = values.first;
    // The portal wraps the setting in a variant, sometimes twice.
    while (value is DBusVariant) {
      value = value.value;
    }
    return switch (value) {
      DBusInt32(:final value) => value,
      DBusUint32(:final value) => value,
      DBusInt64(:final value) => value,
      _ => null,
    };
  }
}

/// Fixed value for widget and unit tests.
class FakeGnomeCursorSizePort implements GnomeCursorSizePort {
  FakeGnomeCursorSizePort(this.value, {this.error});

  int? value;
  Object? error;

  @override
  Future<int?> readCursorSize() async {
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return value;
  }
}

final gnomeCursorSizePortProvider = Provider<GnomeCursorSizePort>(
  (ref) => PortalGnomeCursorSizePort(),
);

/// Cached cursor size; fails open to [defaultCursorSize].
final gnomeCursorSizeProvider = FutureProvider<int>((ref) async {
  try {
    return await ref.watch(gnomeCursorSizePortProvider).readCursorSize() ??
        defaultCursorSize;
  } catch (_) {
    return defaultCursorSize;
  }
});

/// Handle and object-cursor scale for the current system cursor size.
final cursorScaleProvider = Provider<double>((ref) {
  final size = ref.watch(gnomeCursorSizeProvider).asData?.value;
  return cursorScaleFor(size);
});
