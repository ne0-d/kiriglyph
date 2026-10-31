import 'package:kiriglyph/settings/app_settings.dart';
import 'package:kiriglyph/settings/folder_picker.dart';
import 'package:kiriglyph/shortcut/accelerator.dart';
import 'package:kiriglyph/shortcut/shortcut_service.dart';

/// Settings held in memory, so tests never touch the real config folder.
class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore([this.value = const AppSettings()]);

  AppSettings value;
  int saves = 0;

  @override
  Future<AppSettings> load() async => value;

  @override
  Future<void> save(AppSettings settings) async {
    value = settings;
    saves++;
  }
}

final ctrlSuperT = Accelerator({
  AcceleratorModifier.control,
  AcceleratorModifier.superKey,
}, 't');

/// A shortcut service that never runs `gsettings`.
class FakeShortcutService implements ShortcutService {
  FakeShortcutService({
    this.binding,
    Map<String, String> conflicts = const {},
    this.currentFailure,
    this.setFailure,
  }) : conflicts = Map.of(conflicts);

  /// The current shortcut; defaults to none.
  ShortcutBinding? binding;

  /// GNOME accelerator (`<Control>x`) to what already uses it.
  final Map<String, String> conflicts;

  ShortcutException? currentFailure;
  ShortcutException? setFailure;
  final setCalls = <Accelerator>[];

  /// A service whose shortcut is already Ctrl+Super+T.
  factory FakeShortcutService.configured() => FakeShortcutService(
    binding: ShortcutBinding(accelerator: ctrlSuperT, path: '/fake/'),
  );

  @override
  Future<ShortcutBinding?> current() async {
    final failure = currentFailure;
    if (failure != null) {
      throw failure;
    }
    return binding;
  }

  @override
  Future<ShortcutConflict?> findConflict(Accelerator accelerator) async {
    final description = conflicts[accelerator.toGtk()];
    return description == null
        ? null
        : ShortcutConflict(accelerator, description);
  }

  @override
  Future<ShortcutBinding> set(Accelerator accelerator) async {
    final failure = setFailure;
    if (failure != null) {
      throw failure;
    }
    setCalls.add(accelerator);
    return binding = ShortcutBinding(accelerator: accelerator, path: '/fake/');
  }
}

/// A folder chooser that answers with a prepared folder.
class FakeFolderPicker implements FolderPickerPort {
  FakeFolderPicker([this.result]);

  String? result;
  String? lastCurrent;
  int calls = 0;

  @override
  Future<String?> chooseFolder({String? current}) async {
    calls++;
    lastCurrent = current;
    return result;
  }
}
