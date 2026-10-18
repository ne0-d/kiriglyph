import 'dart:async';
import 'dart:ui' show FlutterView, TextDirection;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long a burst of announcements is held so it is spoken as one message.
const announcementCoalesceWindow = Duration(milliseconds: 350);

/// Sends short status messages to the screen reader.
///
/// Flutter's Linux embedder delivers screen-reader output only through
/// `SemanticsService.sendAnnouncement`; live regions, dialogs, route changes
/// and label changes are silent there. Every overlay state change therefore
/// goes through this port. Callers pass state and counts, never recognized
/// text.
abstract interface class OverlayAnnouncer {
  /// Queues [message]. [assertive] messages (errors) interrupt and skip the
  /// rate limit. [immediate] sends without waiting, for the last words
  /// before the window hides. A queued message is replaced by a newer one
  /// with the same [topic], so a run of selection changes is spoken once.
  void announce(
    String message, {
    bool assertive = false,
    bool immediate = false,
    String? topic,
  });
}

/// Delivers one message to the platform.
typedef AnnouncementSink = void Function(String message, bool assertive);

/// Rate-limited announcer: the first message of a burst is sent at once, and
/// anything arriving within [window] is joined into one later message.
class CoalescingAnnouncer implements OverlayAnnouncer {
  CoalescingAnnouncer(
    this._sink, {
    this.window = announcementCoalesceWindow,
    this.maxJoined = 3,
  });

  final AnnouncementSink _sink;
  final Duration window;

  /// Most messages joined into one; older ones are dropped first.
  final int maxJoined;

  final _pending = <({String text, String? topic})>[];
  Timer? _timer;

  @override
  void announce(
    String message, {
    bool assertive = false,
    bool immediate = false,
    String? topic,
  }) {
    final text = message.trim();
    if (text.isEmpty) {
      return;
    }
    if (assertive || immediate) {
      _timer?.cancel();
      final queued = [..._pending.map((m) => m.text), text];
      _pending.clear();
      _sink(_join(queued), assertive);
      _startWindow();
      return;
    }
    if (_timer == null) {
      _sink(text, false);
      _startWindow();
      return;
    }
    if (topic != null) {
      _pending.removeWhere((m) => m.topic == topic);
    }
    if (_pending.isEmpty || _pending.last.text != text) {
      _pending.add((text: text, topic: topic));
    }
  }

  void _startWindow() {
    _timer = Timer(window, _windowEnded);
  }

  void _windowEnded() {
    _timer = null;
    if (_pending.isEmpty) {
      return;
    }
    final message = _join([for (final m in _pending) m.text]);
    _pending.clear();
    _sink(message, false);
    _startWindow();
  }

  String _join(List<String> messages) {
    final kept = messages.length > maxJoined
        ? messages.sublist(messages.length - maxJoined)
        : messages;
    return kept.map((m) => m.replaceAll(RegExp(r'\.$'), '')).join('. ');
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}

/// Sends through `SemanticsService.sendAnnouncement` on the implicit view.
/// Sent regardless of `supportsAnnounce`: the call is harmless where
/// unsupported and the only audible path on Linux.
void sendSemanticsAnnouncement(String message, bool assertive) {
  final binding = WidgetsBinding.instance;
  final FlutterView? view =
      binding.platformDispatcher.implicitView ??
      (binding.platformDispatcher.views.isEmpty
          ? null
          : binding.platformDispatcher.views.first);
  if (view == null) {
    return;
  }
  unawaited(
    SemanticsService.sendAnnouncement(
      view,
      message,
      TextDirection.ltr,
      assertiveness: assertive ? Assertiveness.assertive : Assertiveness.polite,
    ),
  );
}

final overlayAnnouncerProvider = Provider<OverlayAnnouncer>((ref) {
  final announcer = CoalescingAnnouncer(sendSemanticsAnnouncement);
  ref.onDispose(announcer.dispose);
  return announcer;
});

/// Records announcements for tests.
class FakeOverlayAnnouncer implements OverlayAnnouncer {
  final messages = <String>[];
  final assertiveMessages = <String>[];

  String? get last => messages.isEmpty ? null : messages.last;

  @override
  void announce(
    String message, {
    bool assertive = false,
    bool immediate = false,
    String? topic,
  }) {
    if (message.isEmpty) {
      return;
    }
    messages.add(message);
    if (assertive) {
      assertiveMessages.add(message);
    }
  }
}
