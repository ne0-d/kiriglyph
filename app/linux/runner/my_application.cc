#include "my_application.h"

#include <cstring>

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

// Set by scripts/run-dev.sh so `flutter run` starts its own instance instead
// of forwarding its command line to an already-running resident instance.
static constexpr char kDevInstanceEnv[] = "KIRIGLYPH_DEV_INSTANCE";
static constexpr char kChannelName[] = "kiriglyph/app";
static constexpr guint kQuitTimeoutSeconds = 2;

// GNOME animates an unmapped window away; capturing earlier would include it.
static constexpr guint kHideSettleMs = 300;
static constexpr guint kPlacementPollMs = 50;
// The surface enters its output only after the compositor shows the first
// fullscreen buffer; until then GDK guesses the monitor from position 0,0.
static constexpr gint64 kPlacementSettleUs = 150 * G_TIME_SPAN_MILLISECOND;
static constexpr gint64 kPlacementTimeoutUs = 2500 * G_TIME_SPAN_MILLISECOND;
// Focus settles after mapping; a short loss is not a dismissal.
static constexpr guint kFocusOutDebounceMs = 250;
// The normal window maps once Dart has painted its screen; if Dart never
// answers, it maps anyway rather than never appearing.
static constexpr guint kPaintFallbackMs = 800;
// GTK paint cycles to wait after the Flutter view is shown. The first draws
// the frame Flutter has; the next gives one just rasterized time to land.
static constexpr gint kRevealPaints = 2;
// A reveal that never paints must not leave an invisible fullscreen window
// holding the pointer and keyboard.
static constexpr guint kRevealTimeoutMs = 500;
static constexpr char kOverlayStyleClass[] = "kiriglyph-overlay";

struct _MyApplication {
  GtkApplication parent_instance;
  GtkWindow* window;
  GtkWidget* header_bar;
  FlView* view;
  FlMethodChannel* channel;
  // Commands that arrived before Dart registered its channel handler.
  GPtrArray* pending;
  // A resident instance hides its window on close instead of quitting.
  gboolean resident;
  gboolean dart_ready;
  gboolean first_frame;
  gboolean show_requested;
  // The normal window was asked for and Dart is painting its screen; Dart
  // maps the window with `present` once that frame is rendered.
  gboolean awaiting_paint;
  guint present_timeout_id;
  gboolean quitting;
  guint quit_timeout_id;

  // Selection overlay: the same window, fullscreen and undecorated. It maps
  // with Flutter's view hidden, so only GTK's transparent surface shows, and
  // the view is shown once Dart has painted the frozen frame.
  gboolean overlay;
  gboolean overlay_was_active;
  gint normal_width;
  gint normal_height;
  FlMethodCall* prepare_call;
  guint prepare_timeout_id;
  FlMethodCall* placement_call;
  guint placement_poll_id;
  gint64 placement_started_us;
  gint64 placement_size_matched_us;
  FlMethodCall* reveal_call;
  GdkFrameClock* reveal_clock;
  gulong reveal_after_paint_id;
  gint reveal_paints_left;
  guint reveal_timeout_id;
  guint focus_out_timeout_id;
  gboolean suppress_focus_loss;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void clear_source(guint* id) {
  if (*id != 0) {
    g_source_remove(*id);
    *id = 0;
  }
}

static void send_to_dart(MyApplication* self, const char* method);

static void cancel_pending_present(MyApplication* self) {
  self->awaiting_paint = FALSE;
  clear_source(&self->present_timeout_id);
}

// Maps the window. A window maps with the last frame Flutter rendered over
// an opaque black background, so callers only get here once Flutter has
// rendered what the window should show.
static void map_window(MyApplication* self) {
  cancel_pending_present(self);
  self->show_requested = TRUE;
  if (self->first_frame) {
    gtk_window_present(self->window);
  }
}

static gboolean present_timeout_cb(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->present_timeout_id = 0;
  map_window(self);
  return G_SOURCE_REMOVE;
}

static void arm_present_timeout(MyApplication* self) {
  if (self->first_frame && self->present_timeout_id == 0) {
    self->present_timeout_id =
        g_timeout_add(kPaintFallbackMs, present_timeout_cb, self);
  }
}

// Presents the window. The overlay maps at once; its Flutter view stays
// hidden until the reveal. The normal window first asks Dart to paint its
// screen, because the hidden window kept a stale frame (transparent, from
// the overlay) that would show over black until the next frame arrives; Dart
// then maps it through `present`.
static void present_window(MyApplication* self) {
  if (self->overlay) {
    map_window(self);
    return;
  }
  self->show_requested = TRUE;
  if (gtk_widget_get_mapped(GTK_WIDGET(self->window))) {
    // Already on screen with current content; only raise it.
    gtk_window_present(self->window);
    return;
  }
  if (self->awaiting_paint) {
    return;
  }
  self->awaiting_paint = TRUE;
  send_to_dart(self, "presented");
  arm_present_timeout(self);
}

static void send_to_dart(MyApplication* self, const char* method) {
  if (self->dart_ready) {
    fl_method_channel_invoke_method(self->channel, method, nullptr, nullptr,
                                    nullptr, nullptr);
    return;
  }
  for (guint i = 0; i < self->pending->len; i++) {
    if (g_strcmp0(static_cast<char*>(g_ptr_array_index(self->pending, i)),
                  method) == 0) {
      return;
    }
  }
  g_ptr_array_add(self->pending, g_strdup(method));
}

static void finish_quit(MyApplication* self) {
  if (self->quit_timeout_id != 0) {
    g_source_remove(self->quit_timeout_id);
    self->quit_timeout_id = 0;
  }
  g_application_quit(G_APPLICATION(self));
}

static void quit_response_cb(GObject* object, GAsyncResult* result,
                             gpointer user_data) {
  g_autoptr(FlMethodResponse) response = fl_method_channel_invoke_method_finish(
      FL_METHOD_CHANNEL(object), result, nullptr);
  finish_quit(MY_APPLICATION(user_data));
}

static gboolean quit_timeout_cb(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->quit_timeout_id = 0;
  finish_quit(self);
  return G_SOURCE_REMOVE;
}

// Lets Dart discard session files before the engine stops.
static void request_quit(MyApplication* self) {
  if (self->quitting) {
    return;
  }
  self->quitting = TRUE;
  if (!self->dart_ready) {
    finish_quit(self);
    return;
  }
  self->quit_timeout_id =
      g_timeout_add_seconds(kQuitTimeoutSeconds, quit_timeout_cb, self);
  fl_method_channel_invoke_method(self->channel, "quit", nullptr, nullptr,
                                  quit_response_cb, self);
}

static void respond_bool(FlMethodCall* method_call, gboolean value) {
  g_autoptr(FlValue) result = fl_value_new_bool(value);
  fl_method_call_respond_success(method_call, result, nullptr);
}

static void respond_string(FlMethodCall* method_call, const gchar* value) {
  g_autoptr(FlValue) result = value == nullptr ? nullptr : fl_value_new_string(value);
  fl_method_call_respond_success(method_call, result, nullptr);
}

struct ClipboardPngData {
  guint8* bytes;
  gsize length;
};

static void clipboard_get_cb(GtkClipboard* clipboard,
                             GtkSelectionData* selection_data, guint info,
                             gpointer user_data) {
  ClipboardPngData* data = static_cast<ClipboardPngData*>(user_data);
  GdkAtom png = gdk_atom_intern_static_string("image/png");
  gtk_selection_data_set(selection_data, png, 8, data->bytes, data->length);
}

static void clipboard_clear_cb(GtkClipboard* clipboard, gpointer user_data) {
  ClipboardPngData* data = static_cast<ClipboardPngData*>(user_data);
  g_free(data->bytes);
  g_free(data);
}

static void copy_image(MyApplication* self, FlMethodCall* method_call) {
  FlValue* args = fl_method_call_get_args(method_call);
  if (fl_value_get_type(args) != FL_VALUE_TYPE_UINT8_LIST) {
    fl_method_call_respond_error(method_call, "bad_args",
                                 "copyImage expects PNG bytes.", nullptr,
                                 nullptr);
    return;
  }
  const size_t length = fl_value_get_length(args);
  if (length == 0) {
    fl_method_call_respond_error(method_call, "empty_png",
                                 "copyImage received no bytes.", nullptr,
                                 nullptr);
    return;
  }
  const uint8_t* bytes = fl_value_get_uint8_list(args);
  ClipboardPngData* data = static_cast<ClipboardPngData*>(
      g_malloc0(sizeof(ClipboardPngData)));
  data->bytes = static_cast<guint8*>(g_malloc(length));
  std::memcpy(data->bytes, bytes, length);
  data->length = length;
  GtkTargetEntry targets[] = {{const_cast<gchar*>("image/png"), 0, 0}};
  GtkClipboard* clipboard =
      gtk_clipboard_get_for_display(gtk_widget_get_display(GTK_WIDGET(self->window)),
                                    GDK_SELECTION_CLIPBOARD);
  if (!gtk_clipboard_set_with_data(clipboard, targets, 1, clipboard_get_cb,
                                   clipboard_clear_cb, data)) {
    clipboard_clear_cb(clipboard, data);
    fl_method_call_respond_error(method_call, "clipboard_unavailable",
                                 "Could not own the image clipboard.", nullptr,
                                 nullptr);
    return;
  }
  gtk_clipboard_set_can_store(clipboard, targets, 1);
  fl_method_call_respond_success(method_call, nullptr, nullptr);
}

struct SaveDialogData {
  FlMethodCall* method_call;
  GtkFileChooserNative* dialog;
};

static void save_dialog_response_cb(GtkNativeDialog* dialog, gint response,
                                    gpointer user_data) {
  SaveDialogData* data = static_cast<SaveDialogData*>(user_data);
  if (response == GTK_RESPONSE_ACCEPT) {
    g_autofree gchar* filename =
        gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(data->dialog));
    respond_string(data->method_call, filename);
  } else {
    respond_string(data->method_call, nullptr);
  }
  g_object_unref(data->dialog);
  g_object_unref(data->method_call);
  g_free(data);
}

static const gchar* suggested_png_name(FlMethodCall* method_call) {
  FlValue* args = fl_method_call_get_args(method_call);
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return "kiriglyph-subject.png";
  }
  FlValue* value = fl_value_lookup_string(args, "suggestedName");
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return "kiriglyph-subject.png";
  }
  const gchar* name = fl_value_get_string(value);
  return name == nullptr || *name == '\0' ? "kiriglyph-subject.png" : name;
}

static gchar* default_png_name() {
  g_autoptr(GDateTime) now = g_date_time_new_now_local();
  return g_date_time_format(now, "kiriglyph-%Y%m%d-%H%M%S.png");
}

static void choose_save_png(MyApplication* self, FlMethodCall* method_call) {
  GtkFileChooserNative* dialog = gtk_file_chooser_native_new(
      "Save Subject PNG", self->window, GTK_FILE_CHOOSER_ACTION_SAVE, "_Save",
      "_Cancel");
  gtk_native_dialog_set_transient_for(GTK_NATIVE_DIALOG(dialog), self->window);
  gtk_native_dialog_set_modal(GTK_NATIVE_DIALOG(dialog), TRUE);
  GtkFileChooser* chooser = GTK_FILE_CHOOSER(dialog);
  gtk_file_chooser_set_do_overwrite_confirmation(chooser, TRUE);
  const gchar* suggested = suggested_png_name(method_call);
  g_autofree gchar* fallback = nullptr;
  if (g_strcmp0(suggested, "kiriglyph-subject.png") == 0) {
    fallback = default_png_name();
    suggested = fallback;
  }
  gtk_file_chooser_set_current_name(chooser, suggested);
  const gchar* pictures = g_get_user_special_dir(G_USER_DIRECTORY_PICTURES);
  gtk_file_chooser_set_current_folder(
      chooser, pictures != nullptr ? pictures : g_get_home_dir());
  GtkFileFilter* filter = gtk_file_filter_new();
  gtk_file_filter_set_name(filter, "PNG images");
  gtk_file_filter_add_mime_type(filter, "image/png");
  gtk_file_filter_add_pattern(filter, "*.png");
  gtk_file_chooser_add_filter(chooser, filter);

  SaveDialogData* data =
      static_cast<SaveDialogData*>(g_malloc0(sizeof(SaveDialogData)));
  data->method_call = FL_METHOD_CALL(g_object_ref(method_call));
  data->dialog = GTK_FILE_CHOOSER_NATIVE(g_object_ref(dialog));
  g_signal_connect(dialog, "response", G_CALLBACK(save_dialog_response_cb),
                   data);
  gtk_native_dialog_show(GTK_NATIVE_DIALOG(dialog));
  g_object_unref(dialog);
}

static void finish_prepare(MyApplication* self, gboolean was_visible) {
  clear_source(&self->prepare_timeout_id);
  if (self->prepare_call != nullptr) {
    respond_bool(self->prepare_call, was_visible);
    g_clear_object(&self->prepare_call);
  }
}

static gboolean prepare_timeout_cb(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->prepare_timeout_id = 0;
  finish_prepare(self, TRUE);
  return G_SOURCE_REMOVE;
}

// Hides a visible window so the next capture cannot contain it. Responds with
// whether it was visible, after GNOME has removed it from the screen.
static void prepare_capture(MyApplication* self, FlMethodCall* method_call) {
  finish_prepare(self, FALSE);
  cancel_pending_present(self);
  if (self->overlay || !gtk_widget_get_visible(GTK_WIDGET(self->window))) {
    respond_bool(method_call, FALSE);
    return;
  }
  self->show_requested = FALSE;
  gtk_widget_hide(GTK_WIDGET(self->window));
  self->prepare_call = FL_METHOD_CALL(g_object_ref(method_call));
  self->prepare_timeout_id =
      g_timeout_add(kHideSettleMs, prepare_timeout_cb, self);
}

static void fail_placement(MyApplication* self, const char* code,
                           const char* message) {
  clear_source(&self->placement_poll_id);
  if (self->placement_call != nullptr) {
    fl_method_call_respond_error(self->placement_call, code, message, nullptr,
                                 nullptr);
    g_clear_object(&self->placement_call);
  }
}

static void finish_reveal(MyApplication* self) {
  clear_source(&self->reveal_timeout_id);
  if (self->reveal_clock != nullptr) {
    if (self->reveal_after_paint_id != 0) {
      g_signal_handler_disconnect(self->reveal_clock,
                                  self->reveal_after_paint_id);
      self->reveal_after_paint_id = 0;
    }
    gdk_frame_clock_end_updating(self->reveal_clock);
    g_clear_object(&self->reveal_clock);
  }
  if (self->reveal_call != nullptr) {
    fl_method_call_respond_success(self->reveal_call, nullptr, nullptr);
    g_clear_object(&self->reveal_call);
  }
}

static void reveal_after_paint_cb(GdkFrameClock* clock, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (--self->reveal_paints_left > 0) {
    return;
  }
  finish_reveal(self);
}

static gboolean reveal_timeout_cb(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->reveal_timeout_id = 0;
  finish_reveal(self);
  return G_SOURCE_REMOVE;
}

static FlValue* monitor_value(GdkMonitor* monitor) {
  GdkRectangle geometry;
  gdk_monitor_get_geometry(monitor, &geometry);
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(value, "x", fl_value_new_int(geometry.x));
  fl_value_set_string_take(value, "y", fl_value_new_int(geometry.y));
  fl_value_set_string_take(value, "width", fl_value_new_int(geometry.width));
  fl_value_set_string_take(value, "height",
                           fl_value_new_int(geometry.height));
  fl_value_set_string_take(
      value, "scaleFactor",
      fl_value_new_int(gdk_monitor_get_scale_factor(monitor)));
  return value;
}

// Reports the monitor the fullscreen window landed on, with every monitor's
// logical geometry, once the compositor has configured and shown it there.
static gboolean placement_poll_cb(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gint64 now = g_get_monotonic_time();
  if (now - self->placement_started_us > kPlacementTimeoutUs) {
    self->placement_poll_id = 0;
    fail_placement(self, "placement_timeout",
                   "The overlay window was not placed on a display.");
    return G_SOURCE_REMOVE;
  }

  GtkWidget* widget = GTK_WIDGET(self->window);
  GdkWindow* gdk_window = gtk_widget_get_window(widget);
  if (!gtk_widget_get_mapped(widget) || gdk_window == nullptr ||
      (gdk_window_get_state(gdk_window) & GDK_WINDOW_STATE_FULLSCREEN) == 0) {
    return G_SOURCE_CONTINUE;
  }
  GdkDisplay* display = gtk_widget_get_display(widget);
  GdkMonitor* placed = gdk_display_get_monitor_at_window(display, gdk_window);
  if (placed == nullptr) {
    return G_SOURCE_CONTINUE;
  }
  GdkRectangle geometry;
  gdk_monitor_get_geometry(placed, &geometry);
  // A fullscreen configure sizes the window to its monitor; until then the
  // window still has its normal size.
  if (gtk_widget_get_allocated_width(widget) != geometry.width ||
      gtk_widget_get_allocated_height(widget) != geometry.height) {
    self->placement_size_matched_us = 0;
    return G_SOURCE_CONTINUE;
  }
  if (self->placement_size_matched_us == 0) {
    self->placement_size_matched_us = now;
  }
  if (now - self->placement_size_matched_us < kPlacementSettleUs) {
    return G_SOURCE_CONTINUE;
  }

  g_autoptr(FlValue) monitors = fl_value_new_list();
  gint target = -1;
  const gint count = gdk_display_get_n_monitors(display);
  for (gint i = 0; i < count; i++) {
    GdkMonitor* monitor = gdk_display_get_monitor(display, i);
    if (monitor == placed) {
      target = i;
    }
    fl_value_append_take(monitors, monitor_value(monitor));
  }
  if (target < 0) {
    return G_SOURCE_CONTINUE;
  }
  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "target", fl_value_new_int(target));
  fl_value_set_string(result, "monitors", monitors);
  self->placement_poll_id = 0;
  fl_method_call_respond_success(self->placement_call, result, nullptr);
  g_clear_object(&self->placement_call);
  return G_SOURCE_REMOVE;
}

static void set_view_background(MyApplication* self, const char* color) {
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, color);
  fl_view_set_background_color(self->view, &background_color);
}

// Switches the hidden window into a transparent, undecorated fullscreen
// surface. The desktop stays visible through it until the reveal.
//
// Flutter's view is hidden for that time. GDK's Wayland backend ignores
// toplevel opacity, and the view maps with whatever it last rendered over an
// opaque black background, so a mapped view shows black until Flutter paints
// at the new size. With the view hidden, the window shows only what GTK
// paints itself: a transparent surface.
static void enter_overlay_mode(MyApplication* self) {
  self->overlay = TRUE;
  self->overlay_was_active = FALSE;
  GtkWidget* widget = GTK_WIDGET(self->window);
  gtk_window_get_size(self->window, &self->normal_width, &self->normal_height);
  gtk_widget_hide(GTK_WIDGET(self->view));
  if (self->header_bar != nullptr) {
    gtk_widget_hide(self->header_bar);
  }
  gtk_window_set_decorated(self->window, FALSE);
  gtk_style_context_add_class(gtk_widget_get_style_context(widget),
                              kOverlayStyleClass);
  gtk_widget_set_app_paintable(widget, TRUE);
  set_view_background(self, "rgba(0,0,0,0)");
  gtk_window_fullscreen(self->window);
}

// Hides the window first so the user never sees it unfullscreen, then
// restores the normal window for its next presentation.
static void leave_overlay_mode(MyApplication* self) {
  fail_placement(self, "cancelled", "The overlay was dismissed.");
  finish_reveal(self);
  clear_source(&self->focus_out_timeout_id);
  if (!self->overlay) {
    return;
  }
  self->overlay = FALSE;
  self->suppress_focus_loss = FALSE;
  self->show_requested = FALSE;
  cancel_pending_present(self);
  GtkWidget* widget = GTK_WIDGET(self->window);
  gtk_widget_hide(widget);
  gtk_widget_show(GTK_WIDGET(self->view));
  gtk_window_unfullscreen(self->window);
  gtk_window_set_decorated(self->window, TRUE);
  if (self->header_bar != nullptr) {
    gtk_widget_show(self->header_bar);
  }
  gtk_style_context_remove_class(gtk_widget_get_style_context(widget),
                                 kOverlayStyleClass);
  gtk_widget_set_app_paintable(widget, FALSE);
  set_view_background(self, "#000000");
  if (self->normal_width > 0 && self->normal_height > 0) {
    gtk_window_resize(self->window, self->normal_width, self->normal_height);
  }
}

static void show_overlay(MyApplication* self, FlMethodCall* method_call) {
  if (self->placement_call != nullptr) {
    fl_method_call_respond_error(method_call, "busy",
                                 "The overlay is already being placed.",
                                 nullptr, nullptr);
    return;
  }
  finish_prepare(self, FALSE);
  if (!self->overlay) {
    enter_overlay_mode(self);
  }
  self->placement_call = FL_METHOD_CALL(g_object_ref(method_call));
  self->placement_started_us = g_get_monotonic_time();
  self->placement_size_matched_us = 0;
  self->placement_poll_id =
      g_timeout_add(kPlacementPollMs, placement_poll_cb, self);
  present_window(self);
}

static void reveal_overlay(MyApplication* self, FlMethodCall* method_call) {
  if (!self->overlay) {
    fl_method_call_respond_error(method_call, "not_overlay",
                                 "The overlay is not active.", nullptr,
                                 nullptr);
    return;
  }
  if (self->reveal_call != nullptr) {
    fl_method_call_respond_error(method_call, "busy",
                                 "The overlay is already being revealed.",
                                 nullptr, nullptr);
    return;
  }
  // Showing the view makes it draw, and that draw waits for a Flutter frame
  // at the window's size, so the first thing on screen is a rendered frame.
  GtkWidget* widget = GTK_WIDGET(self->window);
  GtkWidget* view = GTK_WIDGET(self->view);
  gtk_widget_show(view);
  gtk_widget_grab_focus(view);
  GdkFrameClock* clock = gtk_widget_get_frame_clock(widget);
  if (clock == nullptr) {
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
  self->reveal_call = FL_METHOD_CALL(g_object_ref(method_call));
  self->reveal_clock = GDK_FRAME_CLOCK(g_object_ref(clock));
  self->reveal_paints_left = kRevealPaints;
  self->reveal_after_paint_id =
      g_signal_connect(clock, "after-paint", G_CALLBACK(reveal_after_paint_cb),
                       self);
  self->reveal_timeout_id =
      g_timeout_add(kRevealTimeoutMs, reveal_timeout_cb, self);
  gdk_frame_clock_begin_updating(clock);
}

static gboolean focus_out_timeout_cb(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->focus_out_timeout_id = 0;
  if (self->overlay && !gtk_window_is_active(self->window)) {
    send_to_dart(self, "overlayFocusLost");
  }
  return G_SOURCE_REMOVE;
}

// Focusing another window or display dismisses the overlay. Losses before
// the overlay was first focused are mapping noise, not user intent.
static void active_changed_cb(GObject* object, GParamSpec* pspec,
                              gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (!self->overlay) {
    return;
  }
  if (self->suppress_focus_loss) {
    clear_source(&self->focus_out_timeout_id);
    return;
  }
  if (gtk_window_is_active(self->window)) {
    self->overlay_was_active = TRUE;
    clear_source(&self->focus_out_timeout_id);
    return;
  }
  if (self->overlay_was_active && self->focus_out_timeout_id == 0) {
    self->focus_out_timeout_id =
        g_timeout_add(kFocusOutDebounceMs, focus_out_timeout_cb, self);
  }
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "ready") == 0) {
    self->dart_ready = TRUE;
    for (guint i = 0; i < self->pending->len; i++) {
      fl_method_channel_invoke_method(
          self->channel,
          static_cast<char*>(g_ptr_array_index(self->pending, i)), nullptr,
          nullptr, nullptr, nullptr);
    }
    g_ptr_array_set_size(self->pending, 0);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "present") == 0) {
    // Dart has painted the screen the window should show.
    map_window(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "prepareCapture") == 0) {
    prepare_capture(self, method_call);
    return;
  } else if (g_strcmp0(method, "showOverlay") == 0) {
    show_overlay(self, method_call);
    return;
  } else if (g_strcmp0(method, "revealOverlay") == 0) {
    reveal_overlay(self, method_call);
    return;
  } else if (g_strcmp0(method, "hideOverlay") == 0) {
    leave_overlay_mode(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setOverlayFocusLossSuppressed") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* value = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                         ? fl_value_lookup_string(args, "suppressed")
                         : nullptr;
    self->suppress_focus_loss =
        value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL
            ? fl_value_get_bool(value)
            : FALSE;
    if (self->suppress_focus_loss) {
      clear_source(&self->focus_out_timeout_id);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "copyImage") == 0) {
    copy_image(self, method_call);
    return;
  } else if (g_strcmp0(method, "chooseSavePng") == 0) {
    choose_save_png(self, method_call);
    return;
  } else if (g_strcmp0(method, "requestQuit") == 0) {
    request_quit(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  self->first_frame = TRUE;
  if (!self->show_requested) {
    return;
  }
  if (self->awaiting_paint) {
    // Dart is painting the window's screen; map it if Dart does not answer.
    arm_present_timeout(self);
  } else {
    gtk_window_present(self->window);
  }
}

static gboolean delete_event_cb(GtkWidget* widget, GdkEvent* event,
                                gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (!self->resident) {
    return FALSE;
  }
  leave_overlay_mode(self);
  self->show_requested = FALSE;
  cancel_pending_present(self);
  gtk_widget_hide(widget);
  send_to_dart(self, "hidden");
  return TRUE;
}

// Clears the overlay window to transparent before Flutter draws over it.
static gboolean window_draw_cb(GtkWidget* widget, cairo_t* cr,
                               gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->overlay) {
    cairo_save(cr);
    cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
    cairo_set_source_rgba(cr, 0, 0, 0, 0);
    cairo_paint(cr);
    cairo_restore(cr);
  }
  return FALSE;
}

static void install_overlay_style() {
  g_autoptr(GtkCssProvider) provider = gtk_css_provider_new();
  // A transparent background also keeps GTK from declaring the surface
  // opaque, which would make the compositor ignore the alpha channel.
  gtk_css_provider_load_from_data(
      provider,
      "window.kiriglyph-overlay { background-color: transparent; "
      "background-image: none; box-shadow: none; }",
      -1, nullptr);
  gtk_style_context_add_provider_for_screen(
      gdk_screen_get_default(), GTK_STYLE_PROVIDER(provider),
      GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
}

// Creates the window and starts the engine without showing the window.
static void create_window(MyApplication* self, char** dart_arguments) {
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  self->window = window;

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
  GdkScreen* screen = gtk_window_get_screen(window);
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Kiriglyph");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
    self->header_bar = GTK_WIDGET(header_bar);
  } else {
    gtk_window_set_title(window, "Kiriglyph");
  }

  // The overlay maps transparent, which needs an alpha visual before realize.
  GdkVisual* rgba_visual = gdk_screen_get_rgba_visual(screen);
  if (rgba_visual != nullptr) {
    gtk_widget_set_visual(GTK_WIDGET(window), rgba_visual);
  }
  install_overlay_style();

  gtk_window_set_default_size(window, 1280, 720);
  g_signal_connect(window, "delete-event", G_CALLBACK(delete_event_cb), self);
  g_signal_connect(window, "notify::is-active", G_CALLBACK(active_changed_cb),
                   self);
  g_signal_connect(window, "draw", G_CALLBACK(window_draw_cb), self);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, dart_arguments);

  FlView* view = fl_view_new(project);
  self->view = view;
  set_view_background(self, "#000000");
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // The window is shown on the first frame only if something asked for it;
  // a background start keeps the engine running with the window hidden.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), kChannelName,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb, self,
                                            nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Handles "command-line" in the primary instance for its own launch and for
// every later launch forwarded over D-Bus. Connected as the first signal
// handler because the signal stops at the first handler that returns, and the
// gtk plugin registers its own handler that would otherwise swallow launches.
static gint command_line_cb(GApplication* application,
                            GApplicationCommandLine* command_line,
                            gpointer user_data) {
  MyApplication* self = MY_APPLICATION(application);
  gint argc = 0;
  g_auto(GStrv) argv =
      g_application_command_line_get_arguments(command_line, &argc);
  gboolean background = FALSE;
  gboolean select = FALSE;
  gboolean quit = FALSE;
  g_autoptr(GPtrArray) dart_arguments = g_ptr_array_new();
  for (gint i = 1; i < argc; i++) {
    if (g_strcmp0(argv[i], "--background") == 0) {
      background = TRUE;
    } else if (g_strcmp0(argv[i], "--select") == 0) {
      select = TRUE;
    } else if (g_strcmp0(argv[i], "--quit") == 0) {
      quit = TRUE;
    } else {
      g_ptr_array_add(dart_arguments, argv[i]);
    }
  }
  if (self->window == nullptr && (background || select)) {
    g_ptr_array_add(dart_arguments, const_cast<char*>("--hidden-start"));
  }
  g_ptr_array_add(dart_arguments, nullptr);

  if (quit) {
    if (self->window != nullptr) {
      request_quit(self);
    }
    return 0;
  }
  if (self->quitting) {
    return 1;
  }
  if (self->window == nullptr) {
    create_window(self, reinterpret_cast<char**>(dart_arguments->pdata));
  }
  if (select) {
    send_to_dart(self, "select");
  } else if (!background) {
    present_window(self);
  }
  return 0;
}

// Implements GApplication::activate, used by D-Bus activation and
// g_application_activate().
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->quitting) {
    return;
  }
  if (self->window == nullptr) {
    char* no_arguments[] = {nullptr};
    create_window(self, no_arguments);
  }
  present_window(self);
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  clear_source(&self->quit_timeout_id);
  clear_source(&self->prepare_timeout_id);
  clear_source(&self->placement_poll_id);
  clear_source(&self->focus_out_timeout_id);
  clear_source(&self->present_timeout_id);
  finish_reveal(self);
  g_clear_object(&self->prepare_call);
  g_clear_object(&self->placement_call);
  g_clear_object(&self->channel);
  g_clear_pointer(&self->pending, g_ptr_array_unref);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->pending = g_ptr_array_new_with_free_func(g_free);
  g_signal_connect(self, "command-line", G_CALLBACK(command_line_cb), nullptr);
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. GNOME's screenshot access dialog also relies
  // on the focused window carrying this ID.
  g_set_prgname(APPLICATION_ID);

  const gboolean dev_instance = g_getenv(kDevInstanceEnv) != nullptr;
  GApplicationFlags flags = G_APPLICATION_HANDLES_COMMAND_LINE;
  if (dev_instance) {
    flags = static_cast<GApplicationFlags>(flags | G_APPLICATION_NON_UNIQUE);
  }
  MyApplication* self = MY_APPLICATION(
      g_object_new(my_application_get_type(), "application-id", APPLICATION_ID,
                   "flags", flags, nullptr));
  self->resident = !dev_instance;
  return self;
}
