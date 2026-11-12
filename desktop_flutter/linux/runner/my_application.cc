#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "desktop_integration.h"
#include "lyrics_view.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  DesktopIntegration* integration;
  LyricsView* lyrics_view;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

namespace {

constexpr int kDefaultWindowWidth = 1280;
constexpr int kDefaultWindowHeight = 720;
constexpr int kMinWindowWidth = 360;
constexpr int kMinWindowHeight = 480;
constexpr int kMaxWindowSize = 16384;

struct SavedWindowSize {
  int width = kDefaultWindowWidth;
  int height = kDefaultWindowHeight;
  gboolean maximized = FALSE;
  guint save_timer = 0;
};

gchar* window_state_path() {
  return g_build_filename(g_get_user_config_dir(), "nekoplayer",
                          "window-state.ini", nullptr);
}

SavedWindowSize load_window_size() {
  SavedWindowSize state;
  g_autofree gchar* path = window_state_path();
  g_autoptr(GKeyFile) file = g_key_file_new();
  if (!g_key_file_load_from_file(file, path, G_KEY_FILE_NONE, nullptr)) {
    return state;
  }
  const gint width =
      g_key_file_get_integer(file, "window", "width", nullptr);
  const gint height =
      g_key_file_get_integer(file, "window", "height", nullptr);
  if (width >= kMinWindowWidth && height >= kMinWindowHeight &&
      width <= kMaxWindowSize && height <= kMaxWindowSize) {
    state.width = width;
    state.height = height;
  }
  state.maximized =
      g_key_file_get_boolean(file, "window", "maximized", nullptr);
  return state;
}

void save_window_size(const SavedWindowSize& state) {
  g_autofree gchar* directory =
      g_build_filename(g_get_user_config_dir(), "nekoplayer", nullptr);
  if (g_mkdir_with_parents(directory, 0700) != 0) return;
  g_autofree gchar* path = window_state_path();
  g_autoptr(GKeyFile) file = g_key_file_new();
  g_key_file_set_integer(file, "window", "width", state.width);
  g_key_file_set_integer(file, "window", "height", state.height);
  g_key_file_set_boolean(file, "window", "maximized", state.maximized);
  g_key_file_save_to_file(file, path, nullptr);
}

gboolean save_window_size_timeout(gpointer user_data) {
  auto* state = static_cast<SavedWindowSize*>(user_data);
  state->save_timer = 0;
  save_window_size(*state);
  return G_SOURCE_REMOVE;
}

// Debounce continuous resize and maximize events; also persists the state if
// the process is terminated without a clean window close.
void schedule_window_size_save(SavedWindowSize* state) {
  if (state->save_timer != 0) g_source_remove(state->save_timer);
  state->save_timer =
      g_timeout_add(500, save_window_size_timeout, state);
}

void window_size_allocate_cb(GtkWidget* widget, GtkAllocation* allocation,
                             gpointer user_data) {
  auto* state = static_cast<SavedWindowSize*>(user_data);
  // A maximized allocation is the screen size, not the restored size.
  if (!state->maximized && !gtk_window_is_maximized(GTK_WINDOW(widget)) &&
      allocation->width > 0 && allocation->height > 0 &&
      (allocation->width != state->width ||
       allocation->height != state->height)) {
    state->width = allocation->width;
    state->height = allocation->height;
    schedule_window_size_save(state);
  }
}

gboolean window_configure_event_cb(GtkWidget* widget, GdkEventConfigure* event,
                                   gpointer user_data) {
  auto* state = static_cast<SavedWindowSize*>(user_data);
  if (!state->maximized && !gtk_window_is_maximized(GTK_WINDOW(widget)) &&
      event->width > 0 && event->height > 0 &&
      (event->width != state->width || event->height != state->height)) {
    state->width = event->width;
    state->height = event->height;
    schedule_window_size_save(state);
  }
  return FALSE;
}

gboolean window_state_event_cb(GtkWidget* widget, GdkEventWindowState* event,
                               gpointer user_data) {
  auto* state = static_cast<SavedWindowSize*>(user_data);
  const gboolean maximized =
      (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0;
  if (maximized != state->maximized) {
    state->maximized = maximized;
    schedule_window_size_save(state);
  }
  return FALSE;
}

gboolean window_delete_event_cb(GtkWidget* widget, GdkEvent*,
                                gpointer user_data) {
  auto* state = static_cast<SavedWindowSize*>(user_data);
  state->maximized = gtk_window_is_maximized(GTK_WINDOW(widget));
  if (state->save_timer != 0) {
    g_source_remove(state->save_timer);
    state->save_timer = 0;
  }
  save_window_size(*state);
  return FALSE;
}

void window_destroy_state_cb(GtkWidget* widget, gpointer user_data) {
  auto* state = static_cast<SavedWindowSize*>(user_data);
  if (state->save_timer != 0) {
    g_source_remove(state->save_timer);
    state->save_timer = 0;
  }
  if (!gtk_window_is_maximized(GTK_WINDOW(widget))) {
    GtkAllocation allocation;
    gtk_widget_get_allocation(widget, &allocation);
    if (allocation.width > 0 && allocation.height > 0) {
      state->width = allocation.width;
      state->height = allocation.height;
    }
  }
  save_window_size(*state);
}

}  // namespace

// Frees the desktop integration while the Flutter engine is still alive; by
// GObject dispose time the engine (and its method channel) is already gone.
static void window_destroy_cb(MyApplication* self, GtkWidget*) {
  desktop_integration_free(self->integration);
  self->integration = nullptr;
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void apply_window_icon(GtkWindow* window) {
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable != nullptr) {
    g_autofree gchar* directory = g_path_get_dirname(executable);
    g_autofree gchar* icon =
        g_build_filename(directory, "data", "nekoplayer.png", nullptr);
    if (g_file_test(icon, G_FILE_TEST_IS_REGULAR)) {
      gtk_window_set_icon_from_file(window, icon, nullptr);
      gtk_window_set_default_icon_from_file(icon, nullptr);
      return;
    }
  }
  gtk_window_set_icon_name(window, "nekoplayer");
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
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
    gtk_header_bar_set_title(header_bar, "NekoPlayer");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "NekoPlayer");
  }

  SavedWindowSize* window_size = g_new0(SavedWindowSize, 1);
  *window_size = load_window_size();
  g_object_set_data_full(G_OBJECT(window), "nekoplayer-window-size",
                         window_size, g_free);
  g_signal_connect(window, "size-allocate",
                   G_CALLBACK(window_size_allocate_cb), window_size);
  g_signal_connect(window, "configure-event",
                   G_CALLBACK(window_configure_event_cb), window_size);
  g_signal_connect(window, "window-state-event",
                   G_CALLBACK(window_state_event_cb), window_size);
  g_signal_connect(window, "delete-event",
                   G_CALLBACK(window_delete_event_cb), window_size);
  g_signal_connect(window, "destroy",
                   G_CALLBACK(window_destroy_state_cb), window_size);

  gtk_window_set_default_size(window, window_size->width, window_size->height);
  gtk_widget_set_size_request(GTK_WIDGET(window), 360, 480);
  if (window_size->maximized) gtk_window_maximize(window);
  apply_window_icon(window);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#111116");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  // The overlay lets the embedded lyrics web view sit above the Flutter view.
  GtkWidget* overlay = gtk_overlay_new();
  gtk_container_add(GTK_CONTAINER(overlay), GTK_WIDGET(view));
  gtk_widget_show(overlay);
  gtk_container_add(GTK_CONTAINER(window), overlay);

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  self->integration = desktop_integration_new(view, window);
  g_signal_connect_swapped(window, "destroy", G_CALLBACK(window_destroy_cb),
                           self);
  self->lyrics_view = lyrics_view_new(view, GTK_OVERLAY(overlay));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  lyrics_view_free(self->lyrics_view);
  self->lyrics_view = nullptr;
  desktop_integration_free(self->integration);
  self->integration = nullptr;
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
