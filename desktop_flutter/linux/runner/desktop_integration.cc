#include "desktop_integration.h"

#include <cmath>
#include <dlfcn.h>
#include <string>
#include <unistd.h>

struct DesktopIntegration {
  FlMethodChannel* channel = nullptr;
  GtkWindow* main_window = nullptr;
  GtkWidget* lyrics_window = nullptr;
  GtkWidget* lyric = nullptr;
  GtkWidget* next_lyric = nullptr;
  GDBusConnection* bus = nullptr;
  GDBusNodeInfo* node = nullptr;
  guint owner = 0;
  guint root_registration = 0;
  guint player_registration = 0;
  std::string track_id = "/org/mpris/MediaPlayer2/TrackList/NoTrack";
  std::string title = "NekoPlayer";
  std::string artist;
  std::string album;
  std::string loop = "None";
  gboolean playing = FALSE;
  gboolean has_track = FALSE;
  gboolean shuffle = FALSE;
  gint64 position = 0;
  gint64 duration = 0;
  double volume = .75;
  double rate = 1;
  gboolean positioning = FALSE;
  GObject* tray = nullptr;
  GDBusProxy* tray_watcher = nullptr;
  gboolean indicator = FALSE;
  gboolean indicator_connected = FALSE;
  GtkWidget* tray_menu = nullptr;
  gulong close_handler = 0;
  gboolean close_to_tray = FALSE;
  gboolean quitting = FALSE;
};

static const char* introspection = R"xml(
<node>
 <interface name="org.mpris.MediaPlayer2">
  <method name="Raise"/>
  <property name="CanQuit" type="b" access="read"/>
  <property name="CanRaise" type="b" access="read"/>
  <property name="HasTrackList" type="b" access="read"/>
  <property name="Identity" type="s" access="read"/>
  <property name="DesktopEntry" type="s" access="read"/>
  <property name="SupportedUriSchemes" type="as" access="read"/>
  <property name="SupportedMimeTypes" type="as" access="read"/>
 </interface>
 <interface name="org.mpris.MediaPlayer2.Player">
  <method name="Next"/><method name="Previous"/><method name="Pause"/>
  <method name="PlayPause"/><method name="Stop"/><method name="Play"/>
  <method name="Seek"><arg name="Offset" type="x" direction="in"/></method>
  <method name="SetPosition"><arg name="TrackId" type="o" direction="in"/><arg name="Position" type="x" direction="in"/></method>
  <signal name="Seeked"><arg name="Position" type="x"/></signal>
  <property name="PlaybackStatus" type="s" access="read"/>
  <property name="LoopStatus" type="s" access="readwrite"/>
  <property name="Rate" type="d" access="readwrite"/>
  <property name="Shuffle" type="b" access="readwrite"/>
  <property name="Metadata" type="a{sv}" access="read"/>
  <property name="Volume" type="d" access="readwrite"/>
  <property name="Position" type="x" access="read"/>
  <property name="MinimumRate" type="d" access="read"/>
  <property name="MaximumRate" type="d" access="read"/>
  <property name="CanGoNext" type="b" access="read"/>
  <property name="CanGoPrevious" type="b" access="read"/>
  <property name="CanPlay" type="b" access="read"/>
  <property name="CanPause" type="b" access="read"/>
  <property name="CanSeek" type="b" access="read"/>
  <property name="CanControl" type="b" access="read"/>
 </interface>
</node>)xml";

static void action(DesktopIntegration* self, const char* name, FlValue* value = nullptr) {
  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(arguments, "action", fl_value_new_string(name));
  if (value != nullptr) fl_value_set_string_take(arguments, "value", value);
  fl_method_channel_invoke_method(self->channel, "action", arguments, nullptr, nullptr, nullptr);
}

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
struct IndicatorApi {
  GObject* (*create)(const gchar*, const gchar*, int) = nullptr;
  void (*status)(GObject*, int) = nullptr;
  void (*menu)(GObject*, GtkMenu*) = nullptr;
};

static const IndicatorApi& indicator_api() {
  static const IndicatorApi api = [] {
    for (const auto* name : {"libayatana-appindicator3.so.1", "libappindicator3.so.1"}) {
      void* module = dlopen(name, RTLD_NOW | RTLD_LOCAL);
      if (module == nullptr) continue;
      IndicatorApi loaded;
      loaded.create = reinterpret_cast<decltype(loaded.create)>(dlsym(module, "app_indicator_new"));
      loaded.status = reinterpret_cast<decltype(loaded.status)>(dlsym(module, "app_indicator_set_status"));
      loaded.menu = reinterpret_cast<decltype(loaded.menu)>(dlsym(module, "app_indicator_set_menu"));
      if (loaded.create != nullptr && loaded.status != nullptr && loaded.menu != nullptr) return loaded;
      dlclose(module);
    }
    return IndicatorApi{};
  }();
  return api;
}

static gboolean tray_host_available(DesktopIntegration* self) {
  if (self->tray_watcher == nullptr) return FALSE;
  g_autofree gchar* owner = g_dbus_proxy_get_name_owner(self->tray_watcher);
  g_autoptr(GVariant) host = g_dbus_proxy_get_cached_property(self->tray_watcher, "IsStatusNotifierHostRegistered");
  return owner != nullptr && host != nullptr && g_variant_is_of_type(host, G_VARIANT_TYPE_BOOLEAN) && g_variant_get_boolean(host);
}

static gboolean tray_available(DesktopIntegration* self) {
  if (self->indicator) return self->indicator_connected && tray_host_available(self);
  return self->tray != nullptr && gtk_status_icon_is_embedded(GTK_STATUS_ICON(self->tray));
}

static void tray_changed(GObject*, GParamSpec*, gpointer data) {
  auto* self = static_cast<DesktopIntegration*>(data);
  const gboolean available = tray_available(self);
  if (!available) {
    self->close_to_tray = FALSE;
    if (!gtk_widget_get_visible(GTK_WIDGET(self->main_window))) gtk_window_present(self->main_window);
  }
  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(arguments, "available", fl_value_new_bool(available));
  fl_method_channel_invoke_method(self->channel, "trayChanged", arguments, nullptr, nullptr, nullptr);
}

static void indicator_connection(GObject*, gboolean connected, gpointer data) {
  auto* self = static_cast<DesktopIntegration*>(data);
  self->indicator_connected = connected;
  tray_changed(nullptr, nullptr, self);
}

static void tray_host_changed(GDBusProxy*, GVariant*, const gchar* const*, gpointer data) {
  tray_changed(nullptr, nullptr, data);
}

static void tray_show(GtkWidget*, gpointer data) {
  gtk_window_present(static_cast<DesktopIntegration*>(data)->main_window);
}

static void tray_toggle(GtkWidget*, gpointer data) { action(static_cast<DesktopIntegration*>(data), "toggle"); }
static void tray_previous(GtkWidget*, gpointer data) { action(static_cast<DesktopIntegration*>(data), "previous"); }
static void tray_next(GtkWidget*, gpointer data) { action(static_cast<DesktopIntegration*>(data), "next"); }
static void tray_quit(GtkWidget*, gpointer data) {
  auto* self = static_cast<DesktopIntegration*>(data);
  self->quitting = TRUE;
  gtk_window_close(self->main_window);
}

static void tray_popup(GtkStatusIcon* icon, guint button, guint time, gpointer data) {
  auto* self = static_cast<DesktopIntegration*>(data);
  gtk_menu_popup(GTK_MENU(self->tray_menu), nullptr, nullptr, gtk_status_icon_position_menu, icon, button, time);
}

static gboolean main_delete(GtkWidget* window, GdkEvent*, gpointer data) {
  auto* self = static_cast<DesktopIntegration*>(data);
  if (!self->quitting && self->close_to_tray && tray_available(self)) {
    gtk_widget_hide(window);
    return TRUE;
  }
  return FALSE;
}

static void start_tray(DesktopIntegration* self) {
  if (self->tray != nullptr) return;
  self->quitting = FALSE;
  self->tray_watcher = g_dbus_proxy_new_for_bus_sync(G_BUS_TYPE_SESSION, G_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START,
      nullptr, "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher", nullptr, nullptr);
  const auto& api = indicator_api();
  self->indicator = api.create != nullptr && tray_host_available(self);
  if (self->indicator) {
    self->tray = api.create("nekoplayer", "multimedia-player", 1);
    if (self->tray == nullptr) self->indicator = FALSE;
  }
  if (!self->indicator) {
    g_clear_object(&self->tray_watcher);
    if (!self->positioning) return;
    self->tray = G_OBJECT(gtk_status_icon_new_from_icon_name("multimedia-player"));
    gtk_status_icon_set_title(GTK_STATUS_ICON(self->tray), "NekoPlayer");
    gtk_status_icon_set_tooltip_text(GTK_STATUS_ICON(self->tray), "NekoPlayer — 点击显示播放器");
  }
  self->tray_menu = gtk_menu_new();
  g_object_ref_sink(self->tray_menu);
  const char* labels[] = {"显示播放器", "播放 / 暂停", "上一首", "下一首", "退出"};
  GCallback callbacks[] = {G_CALLBACK(tray_show), G_CALLBACK(tray_toggle), G_CALLBACK(tray_previous), G_CALLBACK(tray_next), G_CALLBACK(tray_quit)};
  for (int index = 0; index < 5; ++index) {
    GtkWidget* item = gtk_menu_item_new_with_label(labels[index]);
    gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), item);
    g_signal_connect(item, "activate", callbacks[index], self);
  }
  gtk_widget_show_all(self->tray_menu);
  if (self->indicator) {
    g_signal_connect(self->tray, "connection-changed", G_CALLBACK(indicator_connection), self);
    g_signal_connect(self->tray_watcher, "g-properties-changed", G_CALLBACK(tray_host_changed), self);
    g_signal_connect(self->tray_watcher, "notify::g-name-owner", G_CALLBACK(tray_changed), self);
    api.menu(self->tray, GTK_MENU(self->tray_menu));
    api.status(self->tray, 1);
    g_object_get(self->tray, "connected", &self->indicator_connected, nullptr);
  } else {
    g_signal_connect(self->tray, "activate", G_CALLBACK(tray_show), self);
    g_signal_connect(self->tray, "popup-menu", G_CALLBACK(tray_popup), self);
    g_signal_connect(self->tray, "notify::embedded", G_CALLBACK(tray_changed), self);
    gtk_status_icon_set_visible(GTK_STATUS_ICON(self->tray), TRUE);
  }
  self->close_handler = g_signal_connect(self->main_window, "delete-event", G_CALLBACK(main_delete), self);
}

static void stop_tray(DesktopIntegration* self) {
  self->close_to_tray = FALSE;
  if (self->close_handler != 0 && g_signal_handler_is_connected(self->main_window, self->close_handler)) g_signal_handler_disconnect(self->main_window, self->close_handler);
  self->close_handler = 0;
  if (self->tray != nullptr) g_signal_handlers_disconnect_by_data(self->tray, self);
  if (self->tray_watcher != nullptr) g_signal_handlers_disconnect_by_data(self->tray_watcher, self);
  if (self->indicator && self->tray != nullptr) indicator_api().status(self->tray, 0);
  g_clear_object(&self->tray);
  g_clear_object(&self->tray_watcher);
  self->indicator = self->indicator_connected = FALSE;
  if (self->tray_menu != nullptr) {
    gtk_widget_destroy(self->tray_menu);
    g_clear_object(&self->tray_menu);
  }
}
#pragma GCC diagnostic pop

static GVariant* metadata(DesktopIntegration* self) {
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&builder, "{sv}", "mpris:trackid", g_variant_new_object_path(self->track_id.c_str()));
  g_variant_builder_add(&builder, "{sv}", "mpris:length", g_variant_new_int64(self->duration));
  g_variant_builder_add(&builder, "{sv}", "xesam:title", g_variant_new_string(self->title.c_str()));
  const char* artists[] = {self->artist.c_str(), nullptr};
  g_variant_builder_add(&builder, "{sv}", "xesam:artist", g_variant_new_strv(artists, 1));
  g_variant_builder_add(&builder, "{sv}", "xesam:album", g_variant_new_string(self->album.c_str()));
  return g_variant_builder_end(&builder);
}

static GVariant* get_property(GDBusConnection*, const gchar*, const gchar*, const gchar* interface_name,
                              const gchar* property, GError**, gpointer data) {
  auto* self = static_cast<DesktopIntegration*>(data);
  const std::string name(property);
  if (g_str_equal(interface_name, "org.mpris.MediaPlayer2")) {
    if (name == "CanQuit" || name == "HasTrackList") return g_variant_new_boolean(FALSE);
    if (name == "CanRaise") return g_variant_new_boolean(TRUE);
    if (name == "Identity") return g_variant_new_string("NekoPlayer");
    if (name == "DesktopEntry") return g_variant_new_string("top.nekoh2o.nekoplayer_desktop");
    return g_variant_new_strv(nullptr, 0);
  }
  if (name == "Metadata") return metadata(self);
  if (name == "PlaybackStatus") return g_variant_new_string(self->playing ? "Playing" : self->has_track ? "Paused" : "Stopped");
  if (name == "LoopStatus") return g_variant_new_string(self->loop.c_str());
  if (name == "Position") return g_variant_new_int64(self->position);
  if (name == "Volume") return g_variant_new_double(self->volume);
  if (name == "Rate") return g_variant_new_double(self->rate);
  if (name == "MinimumRate") return g_variant_new_double(.5);
  if (name == "MaximumRate") return g_variant_new_double(2);
  if (name == "Shuffle") return g_variant_new_boolean(self->shuffle);
  if (name == "CanControl" || name == "CanPlay") return g_variant_new_boolean(TRUE);
  if (name == "CanSeek") return g_variant_new_boolean(self->has_track && self->duration > 0);
  return g_variant_new_boolean(self->has_track);
}

static gboolean set_property(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                              const gchar* property, GVariant* value, GError** error, gpointer data) {
  auto* self = static_cast<DesktopIntegration*>(data);
  const std::string name(property);
  if (name == "Volume" || name == "Rate") {
    const double number = g_variant_get_double(value);
    if (!std::isfinite(number) || number < 0 || (name == "Rate" && (number < .5 || number > 2))) {
      g_set_error_literal(error, G_DBUS_ERROR, G_DBUS_ERROR_INVALID_ARGS, "Value outside supported range");
      return FALSE;
    }
    action(self, name == "Volume" ? "volume" : "rate", fl_value_new_float(number));
  } else if (name == "LoopStatus") {
    const std::string mode(g_variant_get_string(value, nullptr));
    if (mode != "None" && mode != "Track" && mode != "Playlist") {
      g_set_error_literal(error, G_DBUS_ERROR, G_DBUS_ERROR_INVALID_ARGS, "Unknown loop mode");
      return FALSE;
    }
    action(self, "loop", fl_value_new_string(mode.c_str()));
  } else if (name == "Shuffle") {
    action(self, "shuffle", fl_value_new_bool(g_variant_get_boolean(value)));
  } else {
    g_set_error_literal(error, G_DBUS_ERROR, G_DBUS_ERROR_PROPERTY_READ_ONLY, "Read-only property");
    return FALSE;
  }
  return TRUE;
}

static void method_call(GDBusConnection*, const gchar*, const gchar*, const gchar*, const gchar* method,
                         GVariant* parameters, GDBusMethodInvocation* invocation, gpointer data) {
  auto* self = static_cast<DesktopIntegration*>(data);
  const std::string name(method);
  if (name == "Raise") gtk_window_present(self->main_window);
  else if (name == "Seek") {
    gint64 offset;
    g_variant_get(parameters, "(x)", &offset);
    action(self, "seekRelative", fl_value_new_int(offset));
  } else if (name == "SetPosition") {
    const gchar* track;
    gint64 position;
    g_variant_get(parameters, "(&ox)", &track, &position);
    if (self->track_id == track && position >= 0 && position <= self->duration) action(self, "seek", fl_value_new_int(position));
  } else {
    const char* command = name == "Next" ? "next" : name == "Previous" ? "previous" : name == "Pause" ? "pause" : name == "PlayPause" ? "toggle" : name == "Stop" ? "stop" : name == "Play" ? "play" : nullptr;
    if (command == nullptr) {
      g_dbus_method_invocation_return_error(invocation, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_METHOD, "Unsupported method");
      return;
    }
    action(self, command);
  }
  g_dbus_method_invocation_return_value(invocation, nullptr);
}

static const GDBusInterfaceVTable vtable = {method_call, get_property, set_property, {nullptr}};

static void stop_media(DesktopIntegration* self) {
  if (self->owner != 0) g_bus_unown_name(self->owner);
  self->owner = 0;
  if (self->bus != nullptr) {
    if (self->root_registration != 0) g_dbus_connection_unregister_object(self->bus, self->root_registration);
    if (self->player_registration != 0) g_dbus_connection_unregister_object(self->bus, self->player_registration);
  }
  self->root_registration = self->player_registration = 0;
  g_clear_pointer(&self->node, g_dbus_node_info_unref);
  g_clear_object(&self->bus);
}

static gboolean lyrics_delete(GtkWidget* widget, GdkEvent*, gpointer data) {
  auto* self = static_cast<DesktopIntegration*>(data);
  gtk_widget_hide(widget);
  fl_method_channel_invoke_method(self->channel, "overlayClosed", nullptr, nullptr, nullptr, nullptr);
  return TRUE;
}

static gboolean lyrics_press(GtkWidget* widget, GdkEventButton* event, gpointer data) {
  auto* self = static_cast<DesktopIntegration*>(data);
  if (event->button == 1) {
    if (event->type == GDK_2BUTTON_PRESS) action(self, "toggle");
    else if (self->positioning) gtk_window_begin_move_drag(GTK_WINDOW(widget), event->button, event->x_root, event->y_root, event->time);
  }
  return TRUE;
}

static void create_lyrics(DesktopIntegration* self) {
  self->lyrics_window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  auto* window = GTK_WINDOW(self->lyrics_window);
  gtk_window_set_title(window, "NekoPlayer 桌面歌词");
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_keep_above(window, TRUE);
  gtk_window_set_skip_taskbar_hint(window, TRUE);
  gtk_window_set_accept_focus(window, FALSE);
  gtk_window_set_default_size(window, 760, 120);
  gtk_window_set_position(window, GTK_WIN_POS_CENTER);
  gtk_widget_set_app_paintable(self->lyrics_window, TRUE);
  GdkVisual* visual = gdk_screen_get_rgba_visual(gtk_widget_get_screen(self->lyrics_window));
  if (visual != nullptr) gtk_widget_set_visual(self->lyrics_window, visual);
  GtkWidget* box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  gtk_container_set_border_width(GTK_CONTAINER(box), 14);
  self->lyric = gtk_label_new("");
  self->next_lyric = gtk_label_new("");
  for (auto* label : {self->lyric, self->next_lyric}) {
    gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_END);
    gtk_label_set_max_width_chars(GTK_LABEL(label), 60);
    gtk_box_pack_start(GTK_BOX(box), label, FALSE, FALSE, 0);
  }
  gtk_container_add(GTK_CONTAINER(window), box);
  gtk_widget_add_events(self->lyrics_window, GDK_BUTTON_PRESS_MASK);
  g_signal_connect(self->lyrics_window, "button-press-event", G_CALLBACK(lyrics_press), self);
  g_signal_connect(self->lyrics_window, "delete-event", G_CALLBACK(lyrics_delete), self);
  GtkCssProvider* css = gtk_css_provider_new();
  gtk_css_provider_load_from_data(css, "window { background-color: rgba(17,17,22,0.82); border-radius: 14px; }", -1, nullptr);
  gtk_style_context_add_provider(gtk_widget_get_style_context(self->lyrics_window), GTK_STYLE_PROVIDER(css), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  for (auto* label : {self->lyric, self->next_lyric}) {
    GtkCssProvider* font_css = gtk_css_provider_new();
    gtk_css_provider_load_from_data(font_css, "label { font-family: 'Noto Sans CJK SC', sans-serif; }", -1, nullptr);
    gtk_style_context_add_provider(gtk_widget_get_style_context(label), GTK_STYLE_PROVIDER(font_css), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(font_css);
  }
  g_object_unref(css);
}

static FlValue* lookup(FlValue* values, const char* key) {
  return values != nullptr && fl_value_get_type(values) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(values, key) : nullptr;
}

static std::string text(FlValue* values, const char* key) {
  auto* value = lookup(values, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING ? fl_value_get_string(value) : "";
}

static double number(FlValue* values, const char* key) {
  auto* value = lookup(values, key);
  if (value == nullptr) return 0;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) return fl_value_get_int(value);
  return fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT ? fl_value_get_float(value) : 0;
}

static gboolean boolean(FlValue* values, const char* key) {
  auto* value = lookup(values, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(value);
}

static void update(DesktopIntegration* self, FlValue* values) {
  const auto previous_position = self->position;
  const auto previous_track = self->track_id;
  self->track_id = text(values, "trackId");
  if (!g_variant_is_object_path(self->track_id.c_str())) self->track_id = "/org/mpris/MediaPlayer2/TrackList/NoTrack";
  self->title = text(values, "title"); self->artist = text(values, "artist"); self->album = text(values, "album");
  self->playing = boolean(values, "playing"); self->has_track = boolean(values, "hasTrack");
  self->shuffle = boolean(values, "shuffle"); self->loop = text(values, "loop");
  self->position = number(values, "position"); self->duration = number(values, "duration");
  self->volume = number(values, "volume"); self->rate = number(values, "rate");
  if (self->bus != nullptr) {
    GVariantBuilder changed;
    GVariantBuilder invalidated;
    g_variant_builder_init(&changed, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_init(&invalidated, G_VARIANT_TYPE("as"));
    for (const auto* property : {"Metadata", "PlaybackStatus", "LoopStatus", "Shuffle", "Rate", "Volume", "CanSeek", "CanGoNext", "CanGoPrevious", "CanPause"}) {
      g_variant_builder_add(&changed, "{sv}", property, get_property(nullptr, nullptr, nullptr, "org.mpris.MediaPlayer2.Player", property, nullptr, self));
    }
    g_dbus_connection_emit_signal(self->bus, nullptr, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties", "PropertiesChanged", g_variant_new("(sa{sv}as)", "org.mpris.MediaPlayer2.Player", &changed, &invalidated), nullptr);
    if (previous_track == self->track_id && std::abs(self->position - previous_position) > 1500000) {
      g_dbus_connection_emit_signal(self->bus, nullptr, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "Seeked", g_variant_new("(x)", self->position), nullptr);
    }
  }
  if (!boolean(values, "lyricsVisible")) {
    if (self->lyrics_window != nullptr) gtk_widget_hide(self->lyrics_window);
    return;
  }
  if (self->lyrics_window == nullptr) create_lyrics(self);
  const auto lyric = text(values, "lyric");
  const auto next = text(values, "nextLyric");
  g_autofree char* escaped = g_markup_escape_text(lyric.c_str(), -1);
  g_autofree char* escaped_next = g_markup_escape_text(next.c_str(), -1);
  const double size = CLAMP(number(values, "lyricsSize"), 18, 64);
  g_autofree char* markup = g_strdup_printf("<span foreground='#ff8c96' size='%d' weight='bold'>%s</span>", static_cast<int>(size * PANGO_SCALE), escaped);
  g_autofree char* next_markup = g_strdup_printf("<span foreground='#cac2dc' size='%d'>%s</span>", static_cast<int>(size * .65 * PANGO_SCALE), escaped_next);
  gtk_label_set_markup(GTK_LABEL(self->lyric), markup);
  gtk_label_set_markup(GTK_LABEL(self->next_lyric), next_markup);
  gtk_widget_set_opacity(self->lyrics_window, CLAMP(number(values, "lyricsOpacity"), .25, 1));
  gtk_widget_show_all(self->lyrics_window);
  if (gtk_widget_get_realized(self->lyrics_window)) {
    cairo_region_t* region = boolean(values, "lyricsLocked") ? cairo_region_create() : nullptr;
    gdk_window_input_shape_combine_region(gtk_widget_get_window(self->lyrics_window), region, 0, 0);
    if (region != nullptr) cairo_region_destroy(region);
  }
}

static void bus_closed(GDBusConnection*, gboolean remote_peer_vanished, GError* error, gpointer) {
  g_warning("Session bus closed (remote vanished: %d): %s", remote_peer_vanished,
            error != nullptr ? error->message : "no error");
}

static void keep_alive_on_bus_close() {
  static gboolean done = FALSE;
  if (done) return;
  g_autoptr(GDBusConnection) bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (bus == nullptr) return;
  done = TRUE;
  g_dbus_connection_set_exit_on_close(bus, FALSE);
  g_signal_connect(bus, "closed", G_CALLBACK(bus_closed), nullptr);
}

static void channel_call(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* self = static_cast<DesktopIntegration*>(data);
  const std::string method(fl_method_call_get_name(call));
  g_autoptr(FlValue) result = fl_value_new_map();
  if (method == "initialize") {
    // The session bus is a process-wide singleton: set this before the tray
    // proxy uses it so a bus disconnect cannot exit() the whole app.
    keep_alive_on_bus_close();
    start_tray(self);
    if (self->bus == nullptr) {
      self->bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
      if (self->bus != nullptr) {
        g_dbus_connection_set_exit_on_close(self->bus, FALSE);
        self->node = g_dbus_node_info_new_for_xml(introspection, nullptr);
        self->root_registration = g_dbus_connection_register_object(self->bus, "/org/mpris/MediaPlayer2", self->node->interfaces[0], &vtable, self, nullptr, nullptr);
        self->player_registration = g_dbus_connection_register_object(self->bus, "/org/mpris/MediaPlayer2", self->node->interfaces[1], &vtable, self, nullptr, nullptr);
        const std::string name = "org.mpris.MediaPlayer2.NekoPlayer.instance" + std::to_string(getpid());
        self->owner = g_bus_own_name_on_connection(self->bus, name.c_str(), G_BUS_NAME_OWNER_FLAGS_NONE, nullptr, nullptr, nullptr, nullptr);
      }
    }
    fl_value_set_string_take(result, "media", fl_value_new_bool(self->player_registration != 0 && self->root_registration != 0));
    fl_value_set_string_take(result, "lyrics", fl_value_new_bool(TRUE));
    fl_value_set_string_take(result, "positioning", fl_value_new_bool(self->positioning));
    fl_value_set_string_take(result, "tray", fl_value_new_bool(tray_available(self)));
  } else if (method == "configureTray") {
    self->close_to_tray = boolean(fl_method_call_get_args(call), "closeToTray") && tray_available(self);
    g_autoptr(FlValue) enabled = fl_value_new_bool(self->close_to_tray);
    fl_method_call_respond_success(call, enabled, nullptr);
    return;
  } else if (method == "state") update(self, fl_method_call_get_args(call));
  else if (method == "dispose") {
    stop_tray(self);
    stop_media(self);
    if (self->lyrics_window != nullptr) gtk_widget_hide(self->lyrics_window);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  fl_method_call_respond_success(call, result, nullptr);
}

DesktopIntegration* desktop_integration_new(FlView* view, GtkWindow* window) {
  auto* self = new DesktopIntegration();
  self->main_window = GTK_WINDOW(g_object_ref(window));
  self->positioning = g_strcmp0(G_OBJECT_TYPE_NAME(gtk_widget_get_display(GTK_WIDGET(window))), "GdkX11Display") == 0;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(fl_engine_get_binary_messenger(fl_view_get_engine(view)), "top.nekoh2o/desktop", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, channel_call, self, nullptr);
  return self;
}

void desktop_integration_free(DesktopIntegration* self) {
  if (self == nullptr) return;
  stop_tray(self);
  stop_media(self);
  if (self->lyrics_window != nullptr) gtk_widget_destroy(self->lyrics_window);
  fl_method_channel_set_method_call_handler(self->channel, nullptr, nullptr, nullptr);
  g_clear_object(&self->channel);
  g_clear_object(&self->main_window);
  delete self;
}
