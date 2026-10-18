import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

/// Reads GNOME reduced-motion over the XDG Settings portal.
abstract interface class GnomeReducedMotionPort {
  Future<String?> readReducedMotion();
}

/// Session D-Bus call to `org.freedesktop.portal.Settings.Read`.
class PortalGnomeReducedMotionPort implements GnomeReducedMotionPort {
  PortalGnomeReducedMotionPort({DBusClient? client})
    : _client = client ?? DBusClient.session();

  final DBusClient _client;

  static const _destination = 'org.freedesktop.portal.Desktop';
  static final _path = DBusObjectPath('/org/freedesktop/portal/desktop');
  static const _interface = 'org.freedesktop.portal.Settings';
  static const _namespace = 'org.gnome.desktop.a11y.interface';
  static const _key = 'reduced-motion';

  @override
  Future<String?> readReducedMotion() async {
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
    return unwrapReducedMotion(values.first);
  }
}

/// The portal wraps the setting in a variant, and GNOME's reply wraps it
/// twice (`<<'no-preference'>>`), so unwrap until the string is reached.
@visibleForTesting
String? unwrapReducedMotion(DBusValue value) {
  var inner = value;
  while (inner is DBusVariant) {
    inner = inner.value;
  }
  return inner is DBusString ? inner.value : null;
}

/// Fixed value for widget and unit tests.
class FakeGnomeReducedMotionPort implements GnomeReducedMotionPort {
  FakeGnomeReducedMotionPort(this.value);

  String? value;

  @override
  Future<String?> readReducedMotion() async => value;
}
