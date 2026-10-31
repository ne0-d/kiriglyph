// Private fields are set from named parameters, which cannot start with an
// underscore, so initializing formals do not apply.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io' show pid;

import 'package:dbus/dbus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiriglyph/app/app_shell.dart';
import 'package:kiriglyph/background/autostart.dart';
import 'package:kiriglyph/background/shortcut_pause.dart';

const kdeStatusNotifierWatcher = 'org.kde.StatusNotifierWatcher';
const canonicalStatusNotifierWatcher = 'com.canonical.StatusNotifierWatcher';

/// The bus name this process registers its tray item under. It is unique to
/// the process, the way other tray apps name theirs. A fixed name let the tray
/// host's late clean-up of an old instance delete the entry of a new instance
/// that had registered the same name a moment earlier, so the icon vanished
/// after a quick restart.
String statusNotifierItemBusNameFor(int processId) =>
    'org.freedesktop.StatusNotifierItem-$processId-1';

const statusNotifierItemPath = '/StatusNotifierItem';
const dbusMenuPath = '/MenuBar';

enum TrayVisualState { idle, busy, attention }

enum TrayHostState { unknown, available, missing }

class TrayState {
  const TrayState({
    this.visual = TrayVisualState.idle,
    this.host = TrayHostState.unknown,
    this.statusLabel = 'Ready',
  });

  final TrayVisualState visual;
  final TrayHostState host;
  final String statusLabel;

  TrayState copyWith({
    TrayVisualState? visual,
    TrayHostState? host,
    String? statusLabel,
  }) {
    return TrayState(
      visual: visual ?? this.visual,
      host: host ?? this.host,
      statusLabel: statusLabel ?? this.statusLabel,
    );
  }
}

class TrayActions {
  const TrayActions({
    required this.select,
    required this.open,
    required this.setLaunchAtLogin,
    required this.setPaused,
    required this.quit,
  });

  final Future<void> Function() select;
  final Future<void> Function() open;
  final Future<void> Function(bool enabled) setLaunchAtLogin;
  final Future<void> Function(bool paused) setPaused;
  final Future<void> Function() quit;
}

class TrayMenuEntry {
  const TrayMenuEntry({
    required this.id,
    required this.label,
    this.enabled = true,
    this.separator = false,
    this.toggleState,
  });

  final int id;
  final String label;
  final bool enabled;
  final bool separator;
  final bool? toggleState;
}

class TrayMenuModel {
  const TrayMenuModel({
    required this.statusLabel,
    required this.launchAtLogin,
    required this.paused,
  });

  static const status = 1;
  static const select = 2;
  static const open = 3;
  static const launch = 4;
  static const pause = 5;
  static const separator = 6;
  static const quit = 7;

  final String statusLabel;
  final bool launchAtLogin;
  final bool paused;

  List<TrayMenuEntry> get entries => [
    TrayMenuEntry(id: status, label: statusLabel, enabled: false),
    const TrayMenuEntry(id: select, label: 'Select text or object'),
    const TrayMenuEntry(id: open, label: 'Open Kiriglyph'),
    TrayMenuEntry(
      id: launch,
      label: 'Launch at login',
      toggleState: launchAtLogin,
    ),
    TrayMenuEntry(id: pause, label: 'Pause shortcut', toggleState: paused),
    const TrayMenuEntry(id: separator, label: '', separator: true),
    const TrayMenuEntry(id: quit, label: 'Quit'),
  ];
}

abstract interface class StatusNotifierBus {
  Stream<String> get watcherAppeared;

  Future<bool> nameHasOwner(String name);

  Future<void> ownName(String name);

  Future<void> registerObject(DBusObject object);

  Future<void> unregisterObject(DBusObject object);

  Future<void> registerStatusNotifierItem(String watcherName, String service);

  Future<void> close();
}

class DBusStatusNotifierBus implements StatusNotifierBus {
  DBusStatusNotifierBus({DBusClient? client})
    : _client = client ?? DBusClient.session();

  final DBusClient _client;

  @override
  Stream<String> get watcherAppeared => _client.nameOwnerChanged
      .where(
        (event) =>
            (event.name == kdeStatusNotifierWatcher ||
                event.name == canonicalStatusNotifierWatcher) &&
            event.newOwner != null,
      )
      .map((event) => event.name);

  @override
  Future<bool> nameHasOwner(String name) => _client.nameHasOwner(name);

  @override
  Future<void> ownName(String name) async {
    await _client.requestName(name, flags: {DBusRequestNameFlag.doNotQueue});
  }

  @override
  Future<void> registerObject(DBusObject object) =>
      _client.registerObject(object);

  @override
  Future<void> unregisterObject(DBusObject object) =>
      _client.unregisterObject(object);

  @override
  Future<void> registerStatusNotifierItem(
    String watcherName,
    String service,
  ) async {
    await _client.callMethod(
      destination: watcherName,
      path: const DBusObjectPath.unchecked('/StatusNotifierWatcher'),
      interface: watcherName,
      name: 'RegisterStatusNotifierItem',
      values: [DBusString(service)],
      replySignature: DBusSignature.empty,
    );
  }

  @override
  Future<void> close() => _client.close();
}

class StatusNotifierService {
  StatusNotifierService({
    required StatusNotifierBus bus,
    required TrayActions actions,
    TrayState initialState = const TrayState(),
    String? itemName,
  }) : _bus = bus,
       _actions = actions,
       _itemName = itemName ?? statusNotifierItemBusNameFor(pid),
       _stateController = StreamController<TrayState>.broadcast() {
    _state = initialState;
  }

  final StatusNotifierBus _bus;
  final TrayActions _actions;
  final String _itemName;
  final StreamController<TrayState> _stateController;
  late TrayState _state;
  late final _StatusNotifierItemObject _item = _StatusNotifierItemObject(this);
  late final _DBusMenuObject _menu = _DBusMenuObject(this);
  StreamSubscription<String>? _watcherSubscription;
  bool _registeredObjects = false;
  bool _launchAtLogin = false;
  bool _paused = false;
  int _revision = 1;

  Stream<TrayState> get states => _stateController.stream;

  TrayState get state => _state;

  TrayMenuModel get menu => TrayMenuModel(
    statusLabel: _state.statusLabel,
    launchAtLogin: _launchAtLogin,
    paused: _paused,
  );

  int get revision => _revision;

  Future<void> start({
    required bool launchAtLogin,
    required bool paused,
  }) async {
    _launchAtLogin = launchAtLogin;
    _paused = paused;
    await _ensureObjectsRegistered();
    _watcherSubscription ??= _bus.watcherAppeared.listen((_) {
      unawaited(_registerWithWatcher());
    });
    await _registerWithWatcher();
  }

  Future<void> update({
    TrayVisualState? visual,
    String? statusLabel,
    bool? launchAtLogin,
    bool? paused,
  }) async {
    if (launchAtLogin != null) {
      _launchAtLogin = launchAtLogin;
    }
    if (paused != null) {
      _paused = paused;
    }
    _revision++;
    _setState(_state.copyWith(visual: visual, statusLabel: statusLabel));
    await _item.emitPropertiesChanged(
      _StatusNotifierItemObject.interface,
      changedProperties: _item.properties,
    );
    await _menu.emitSignal('com.canonical.dbusmenu', 'LayoutUpdated', [
      DBusUint32(_revision),
      const DBusInt32(0),
    ]);
  }

  Future<void> dispose() async {
    await _watcherSubscription?.cancel();
    if (_registeredObjects) {
      await _bus.unregisterObject(_menu);
      await _bus.unregisterObject(_item);
    }
    await _bus.close();
    await _stateController.close();
  }

  Future<void> activateMenuItem(int id) async {
    switch (id) {
      case TrayMenuModel.select:
        await _actions.select();
      case TrayMenuModel.open:
        await _actions.open();
      case TrayMenuModel.launch:
        await _actions.setLaunchAtLogin(!_launchAtLogin);
        await update(launchAtLogin: !_launchAtLogin);
      case TrayMenuModel.pause:
        await _actions.setPaused(!_paused);
        await update(paused: !_paused);
      case TrayMenuModel.quit:
        await _actions.quit();
    }
  }

  Future<void> _ensureObjectsRegistered() async {
    if (_registeredObjects) {
      return;
    }
    await _bus.ownName(_itemName);
    await _bus.registerObject(_item);
    await _bus.registerObject(_menu);
    _registeredObjects = true;
  }

  Future<void> _registerWithWatcher() async {
    final watcher = await _currentWatcher();
    if (watcher == null) {
      _setState(_state.copyWith(host: TrayHostState.missing));
      return;
    }
    await _bus.registerStatusNotifierItem(watcher, _itemName);
    _setState(_state.copyWith(host: TrayHostState.available));
  }

  Future<String?> _currentWatcher() async {
    if (await _bus.nameHasOwner(kdeStatusNotifierWatcher)) {
      return kdeStatusNotifierWatcher;
    }
    if (await _bus.nameHasOwner(canonicalStatusNotifierWatcher)) {
      return canonicalStatusNotifierWatcher;
    }
    return null;
  }

  void _setState(TrayState state) {
    _state = state;
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }
}

class _StatusNotifierItemObject extends DBusObject {
  _StatusNotifierItemObject(this._service)
    : super(const DBusObjectPath.unchecked(statusNotifierItemPath));

  static const interface = 'org.kde.StatusNotifierItem';

  final StatusNotifierService _service;

  Map<String, DBusValue> get properties => {
    'Category': const DBusString('ApplicationStatus'),
    'Id': const DBusString('kiriglyph'),
    'Title': const DBusString('Kiriglyph'),
    'Status': DBusString(switch (_service.state.visual) {
      TrayVisualState.idle => 'Active',
      TrayVisualState.busy => 'Active',
      TrayVisualState.attention => 'NeedsAttention',
    }),
    'IconName': DBusString(switch (_service.state.visual) {
      TrayVisualState.idle => 'kiriglyph-symbolic',
      TrayVisualState.busy => 'kiriglyph-busy-symbolic',
      TrayVisualState.attention => 'kiriglyph-attention-symbolic',
    }),
    'AttentionIconName': const DBusString('kiriglyph-attention-symbolic'),
    'Menu': const DBusObjectPath.unchecked(dbusMenuPath),
    'ItemIsMenu': const DBusBoolean(true),
  };

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != _StatusNotifierItemObject.interface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final value = properties[name];
    if (value == null) {
      return DBusMethodErrorResponse.unknownProperty();
    }
    return DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != _StatusNotifierItemObject.interface) {
      return DBusGetAllPropertiesResponse({});
    }
    return DBusGetAllPropertiesResponse(properties);
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != _StatusNotifierItemObject.interface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    if (methodCall.name == 'Activate' ||
        methodCall.name == 'SecondaryActivate') {
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}

class _DBusMenuObject extends DBusObject {
  _DBusMenuObject(this._service)
    : super(const DBusObjectPath.unchecked(dbusMenuPath));

  final StatusNotifierService _service;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != 'com.canonical.dbusmenu') {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (methodCall.name) {
      case 'GetLayout':
        return DBusMethodSuccessResponse([
          DBusUint32(_service.revision),
          _layoutNode(0, _service.menu.entries),
        ]);
      case 'Event':
        final id = methodCall.values.first.asInt32();
        final eventId = methodCall.values[1].asString();
        if (eventId == 'clicked') {
          unawaited(_service.activateMenuItem(id));
        }
        return DBusMethodSuccessResponse();
      case 'AboutToShow':
        return DBusMethodSuccessResponse([const DBusBoolean(false)]);
      case 'GetGroupProperties':
        final ids = methodCall.values.first.asInt32Array();
        return DBusMethodSuccessResponse([
          DBusArray(
            DBusSignature('(ia{sv})'),
            ids.map(
              (id) => DBusStruct([
                DBusInt32(id),
                _entryProperties(
                  _service.menu.entries.firstWhere(
                    (entry) => entry.id == id,
                    orElse: () => TrayMenuEntry(id: id, label: ''),
                  ),
                ),
              ]),
            ),
          ),
        ]);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

DBusStruct _layoutNode(int id, List<TrayMenuEntry> entries) {
  return DBusStruct([
    DBusInt32(id),
    DBusDict.stringVariant(const {}),
    DBusArray.variant(
      entries.map((entry) {
        return DBusStruct([
          DBusInt32(entry.id),
          _entryProperties(entry),
          DBusArray.variant(const []),
        ]);
      }),
    ),
  ]);
}

DBusDict _entryProperties(TrayMenuEntry entry) {
  return DBusDict.stringVariant({
    'label': DBusString(entry.label),
    'enabled': DBusBoolean(entry.enabled),
    'visible': const DBusBoolean(true),
    if (entry.separator) 'type': const DBusString('separator'),
    if (entry.toggleState != null) ...{
      'toggle-type': const DBusString('checkmark'),
      'toggle-state': DBusInt32(entry.toggleState! ? 1 : 0),
    },
  });
}

final trayStateProvider = NotifierProvider<TrayStateController, TrayState>(
  TrayStateController.new,
);

class TrayStateController extends Notifier<TrayState> {
  @override
  TrayState build() => const TrayState();

  void setVisual(TrayVisualState visual, {String? statusLabel}) {
    state = state.copyWith(visual: visual, statusLabel: statusLabel);
  }

  void setHost(TrayHostState host) {
    state = state.copyWith(host: host);
  }
}

final statusNotifierBusProvider = Provider<StatusNotifierBus>((ref) {
  final bus = DBusStatusNotifierBus();
  ref.onDispose(bus.close);
  return bus;
});

final statusNotifierServiceProvider = Provider<StatusNotifierService>((ref) {
  throw UnimplementedError('StatusNotifierService is created by AppLifecycle.');
});

/// What the tray menu does, wired to the app.
TrayActions trayActionsFor(
  ProviderContainer container, {
  required Future<void> Function() select,
}) {
  return TrayActions(
    select: select,
    // Not `present`: a window the user closed has its main screen switched
    // off, and only the native request switches it back on before mapping.
    open: container.read(appShellProvider).requestPresent,
    setLaunchAtLogin: (enabled) =>
        container.read(launchAtLoginProvider.notifier).setEnabled(enabled),
    setPaused: (paused) async =>
        container.read(shortcutPauseProvider.notifier).setPaused(paused),
    quit: container.read(appShellProvider).requestQuit,
  );
}

Future<StatusNotifierService> startStatusNotifier({
  required ProviderContainer container,
  required Future<void> Function() select,
}) async {
  final service = StatusNotifierService(
    bus: container.read(statusNotifierBusProvider),
    actions: trayActionsFor(container, select: select),
    initialState: container.read(trayStateProvider),
  );
  container.listen(trayStateProvider, (_, next) {
    unawaited(
      service.update(visual: next.visual, statusLabel: next.statusLabel),
    );
  });
  service.states.listen((state) {
    if (container.read(trayStateProvider).host != state.host) {
      container.read(trayStateProvider.notifier).setHost(state.host);
    }
  });
  final launchAtLogin = await container.read(launchAtLoginProvider.future);
  final paused = container.read(shortcutPauseProvider);
  await service.start(launchAtLogin: launchAtLogin, paused: paused);
  return service;
}
