import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kiriglyph/tray/status_notifier.dart';

void main() {
  test(
    'the tray item is named for its process, not with a shared name',
    () async {
      final bus = _FakeStatusNotifierBus()
        ..ownedNames.add(kdeStatusNotifierWatcher);
      final service = StatusNotifierService(bus: bus, actions: _actions());

      await service.start(launchAtLogin: false, paused: false);

      // A fixed name let the host's late clean-up of an old instance delete the
      // registration of a new one that reused the name after a quick restart.
      expect(
        bus.claimedNames.single,
        matches(RegExp(r'^org\.freedesktop\.StatusNotifierItem-\d+-1$')),
      );
      expect(bus.registeredServices, bus.claimedNames);
      expect(statusNotifierItemBusNameFor(4242), endsWith('-4242-1'));
    },
  );

  test('two instances never share a tray name', () async {
    final first = _FakeStatusNotifierBus()
      ..ownedNames.add(kdeStatusNotifierWatcher);
    final second = _FakeStatusNotifierBus()
      ..ownedNames.add(kdeStatusNotifierWatcher);

    await StatusNotifierService(
      bus: first,
      actions: _actions(),
      itemName: statusNotifierItemBusNameFor(100),
    ).start(launchAtLogin: false, paused: false);
    await StatusNotifierService(
      bus: second,
      actions: _actions(),
      itemName: statusNotifierItemBusNameFor(101),
    ).start(launchAtLogin: false, paused: false);

    expect(
      first.registeredServices.single,
      isNot(second.registeredServices.single),
    );
  });

  test(
    'registers when a watcher exists and re-registers when one appears',
    () async {
      final bus = _FakeStatusNotifierBus();
      final service = StatusNotifierService(bus: bus, actions: _actions());

      await service.start(launchAtLogin: false, paused: false);
      expect(service.state.host, TrayHostState.missing);
      expect(bus.registeredItems, isEmpty);

      bus.ownedNames.add(kdeStatusNotifierWatcher);
      bus.appear(kdeStatusNotifierWatcher);
      await Future<void>.delayed(Duration.zero);

      expect(service.state.host, TrayHostState.available);
      expect(bus.registeredItems, [kdeStatusNotifierWatcher]);
      expect(
        bus.objects.map((object) => object.path.value),
        contains(dbusMenuPath),
      );
    },
  );

  test(
    'dbusmenu layout exposes status, actions, checkboxes and separator',
    () async {
      final bus = _FakeStatusNotifierBus()
        ..ownedNames.add(kdeStatusNotifierWatcher);
      final service = StatusNotifierService(
        bus: bus,
        actions: _actions(),
        initialState: const TrayState(
          statusLabel: 'Screenshot permission needed',
        ),
      );

      await service.start(launchAtLogin: true, paused: true);

      final menu = bus.objects.singleWhere(
        (object) => object.path.value == dbusMenuPath,
      );
      final response = await menu.handleMethodCall(
        const DBusMethodCall(
          sender: ':1.10',
          interface: 'com.canonical.dbusmenu',
          name: 'GetLayout',
        ),
      );
      final root = response.returnValues[1].asStruct();
      final children = root[2].asArray();
      final labels = children.map((child) {
        final props = child.asVariant().asStruct()[1].asStringVariantDict();
        return props['label']!.asString();
      }).toList();

      expect(labels, [
        'Screenshot permission needed',
        'Select text or object',
        'Open Kiriglyph',
        'Launch at login',
        'Pause shortcut',
        '',
        'Quit',
      ]);
      final launchProps = children[3]
          .asVariant()
          .asStruct()[1]
          .asStringVariantDict();
      expect(launchProps['toggle-state']!.asInt32(), 1);
      final pauseProps = children[4]
          .asVariant()
          .asStruct()[1]
          .asStringVariantDict();
      expect(pauseProps['toggle-state']!.asInt32(), 1);
      final separatorProps = children[5]
          .asVariant()
          .asStruct()[1]
          .asStringVariantDict();
      expect(separatorProps['type']!.asString(), 'separator');
    },
  );

  test('menu clicks call app actions', () async {
    final calls = <String>[];
    final service = StatusNotifierService(
      bus: _FakeStatusNotifierBus()..ownedNames.add(kdeStatusNotifierWatcher),
      actions: _actions(calls),
    );

    await service.start(launchAtLogin: false, paused: false);
    await service.activateMenuItem(TrayMenuModel.select);
    await service.activateMenuItem(TrayMenuModel.open);
    await service.activateMenuItem(TrayMenuModel.launch);
    await service.activateMenuItem(TrayMenuModel.pause);
    await service.activateMenuItem(TrayMenuModel.quit);

    expect(calls, ['select', 'open', 'launch:true', 'pause:true', 'quit']);
  });
}

TrayActions _actions([List<String>? calls]) {
  return TrayActions(
    select: () async => calls?.add('select'),
    open: () async => calls?.add('open'),
    setLaunchAtLogin: (enabled) async => calls?.add('launch:$enabled'),
    setPaused: (paused) async => calls?.add('pause:$paused'),
    quit: () async => calls?.add('quit'),
  );
}

class _FakeStatusNotifierBus implements StatusNotifierBus {
  final ownedNames = <String>{};
  final registeredItems = <String>[];
  final claimedNames = <String>[];
  final registeredServices = <String>[];
  final objects = <DBusObject>[];
  final _watchers = StreamController<String>.broadcast();

  @override
  Stream<String> get watcherAppeared => _watchers.stream;

  void appear(String name) => _watchers.add(name);

  @override
  Future<bool> nameHasOwner(String name) async => ownedNames.contains(name);

  @override
  Future<void> ownName(String name) async => claimedNames.add(name);

  @override
  Future<void> registerObject(DBusObject object) async => objects.add(object);

  @override
  Future<void> unregisterObject(DBusObject object) async =>
      objects.remove(object);

  @override
  Future<void> registerStatusNotifierItem(
    String watcherName,
    String service,
  ) async {
    registeredItems.add(watcherName);
    registeredServices.add(service);
  }

  @override
  Future<void> close() => _watchers.close();
}
