#include "lyrics_view.h"

#include <dlfcn.h>
#include <cmath>
#include <string>

namespace {
// WebKitGTK is only declared here and resolved with dlopen: the runner must
// start (and fall back to the browser) on systems without it.
struct WebKitApi {
  void* handle = nullptr;
  GType (*view_get_type)() = nullptr;
  void (*view_load_uri)(void*, const char*) = nullptr;
  void* (*view_get_settings)(void*) = nullptr;
  void (*view_set_background_color)(void*, const GdkRGBA*) = nullptr;
  void* (*view_get_data_manager)(void*) = nullptr;
  void (*settings_set_enable_webgl)(void*, gboolean) = nullptr;
  void (*settings_set_enable_developer_extras)(void*, gboolean) = nullptr;
  void (*manager_set_proxy_settings)(void*, int, void*) = nullptr;
};

constexpr int kNetworkProxyModeNoProxy = 1;

template <typename T>
bool resolve(void* handle, const char* name, T* target) {
  *target = reinterpret_cast<T>(dlsym(handle, name));
  return *target != nullptr;
}

bool load_api(WebKitApi* api, std::string* reason) {
  if (api->handle != nullptr) return true;
  void* handle = dlopen("libwebkit2gtk-4.1.so.0", RTLD_NOW | RTLD_LOCAL);
  if (handle == nullptr) {
    const char* detail = dlerror();
    *reason = std::string("未找到 libwebkit2gtk-4.1，请安装 libwebkit2gtk-4.1-0 后重启") +
              (detail == nullptr ? "" : "（" + std::string(detail) + "）");
    return false;
  }
  WebKitApi found;
  found.handle = handle;
  const bool complete =
      resolve(handle, "webkit_web_view_get_type", &found.view_get_type) &&
      resolve(handle, "webkit_web_view_load_uri", &found.view_load_uri) &&
      resolve(handle, "webkit_web_view_get_settings", &found.view_get_settings) &&
      resolve(handle, "webkit_web_view_set_background_color", &found.view_set_background_color) &&
      resolve(handle, "webkit_settings_set_enable_webgl", &found.settings_set_enable_webgl);
  if (!complete) {
    dlclose(handle);
    *reason = "libwebkit2gtk-4.1 版本过旧，缺少必要接口";
    return false;
  }
  // Optional hardening / diagnostics.
  resolve(handle, "webkit_web_view_get_website_data_manager", &found.view_get_data_manager);
  resolve(handle, "webkit_settings_set_enable_developer_extras", &found.settings_set_enable_developer_extras);
  resolve(handle, "webkit_website_data_manager_set_network_proxy_settings", &found.manager_set_proxy_settings);
  *api = found;
  return true;
}

FlValue* lookup(FlValue* values, const char* key) {
  return values != nullptr && fl_value_get_type(values) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(values, key) : nullptr;
}

std::string text(FlValue* values, const char* key) {
  auto* value = lookup(values, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING ? fl_value_get_string(value) : "";
}

double number(FlValue* values, const char* key) {
  auto* value = lookup(values, key);
  if (value == nullptr) return 0;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) return static_cast<double>(fl_value_get_int(value));
  return fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT ? fl_value_get_float(value) : 0;
}

bool boolean(FlValue* values, const char* key) {
  auto* value = lookup(values, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(value);
}
}  // namespace

struct LyricsView {
  FlView* flutter_view = nullptr;
  GtkOverlay* overlay = nullptr;
  FlMethodChannel* channel = nullptr;
  WebKitApi api;
  GtkWidget* web_view = nullptr;
  GdkRectangle bounds = {0, 0, 1, 1};
};

static void emit_event(LyricsView* self, const char* type, const char* message) {
  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(arguments, "type", fl_value_new_string(type));
  fl_value_set_string_take(arguments, "message", fl_value_new_string(message == nullptr ? "" : message));
  fl_method_channel_invoke_method(self->channel, "event", arguments, nullptr, nullptr, nullptr);
}

static gboolean child_position(GtkOverlay*, GtkWidget* widget, GdkRectangle* allocation, gpointer data) {
  auto* self = static_cast<LyricsView*>(data);
  if (widget != self->web_view) return FALSE;
  *allocation = self->bounds;
  return TRUE;
}

static gboolean load_failed(GtkWidget*, int, const char*, GError* error, gpointer data) {
  emit_event(static_cast<LyricsView*>(data), "loadFailed", error == nullptr ? nullptr : error->message);
  return FALSE;
}

static void process_terminated(GtkWidget*, int, gpointer data) {
  emit_event(static_cast<LyricsView*>(data), "crashed", "动态歌词渲染进程已退出");
}

static gboolean suppress_context_menu(GtkWidget*, gpointer, gpointer, gpointer, gpointer) { return TRUE; }

static void give_focus_back(LyricsView* self) {
  gtk_widget_grab_focus(GTK_WIDGET(self->flutter_view));
}

static void destroy_view(LyricsView* self) {
  if (self->web_view == nullptr) return;
  GtkWidget* web_view = self->web_view;
  self->web_view = nullptr;
  g_signal_handlers_disconnect_by_data(web_view, self);
  gtk_widget_destroy(web_view);
  give_focus_back(self);
}

static bool create_view(LyricsView* self, const std::string& uri, const GdkRGBA& background, std::string* error) {
  if (!g_str_has_prefix(uri.c_str(), "http://127.0.0.1:")) {
    *error = "只允许加载本机动态歌词页面";
    return false;
  }
  if (!load_api(&self->api, error)) return false;
  destroy_view(self);
  // An ephemeral view keeps cookies/cache of the lyrics page out of the profile.
  GtkWidget* web_view = GTK_WIDGET(g_object_new(self->api.view_get_type(), "is-ephemeral", TRUE, nullptr));
  if (web_view == nullptr) {
    *error = "无法创建 WebKitGTK 视图";
    return false;
  }
  void* settings = self->api.view_get_settings(web_view);
  if (settings != nullptr) {
    self->api.settings_set_enable_webgl(settings, TRUE);
    if (self->api.settings_set_enable_developer_extras != nullptr) self->api.settings_set_enable_developer_extras(settings, g_getenv("NEKOPLAYER_LYRICS_DEBUG") != nullptr);
  }
  if (self->api.view_get_data_manager != nullptr && self->api.manager_set_proxy_settings != nullptr) {
    void* manager = self->api.view_get_data_manager(web_view);
    if (manager != nullptr) self->api.manager_set_proxy_settings(manager, kNetworkProxyModeNoProxy, nullptr);
  }
  self->api.view_set_background_color(web_view, &background);
  g_signal_connect(web_view, "load-failed", G_CALLBACK(load_failed), self);
  g_signal_connect(web_view, "web-process-terminated", G_CALLBACK(process_terminated), self);
  g_signal_connect(web_view, "context-menu", G_CALLBACK(suppress_context_menu), self);
  self->web_view = web_view;
  gtk_overlay_add_overlay(self->overlay, web_view);
  self->api.view_load_uri(web_view, uri.c_str());
  return true;
}

static void channel_call(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* self = static_cast<LyricsView*>(data);
  const std::string method(fl_method_call_get_name(call));
  FlValue* arguments = fl_method_call_get_args(call);
  g_autoptr(FlValue) result = fl_value_new_map();
  std::string reason;
  if (method == "isAvailable") {
    const bool available = load_api(&self->api, &reason);
    fl_value_set_string_take(result, "available", fl_value_new_bool(available));
    if (!available) fl_value_set_string_take(result, "reason", fl_value_new_string(reason.c_str()));
  } else if (method == "create") {
    GdkRGBA background = {0x14 / 255., 0x13 / 255., 0x1b / 255., 1};
    const auto color = static_cast<guint32>(number(arguments, "background"));
    if (lookup(arguments, "background") != nullptr) {
      background = {((color >> 16) & 0xff) / 255., ((color >> 8) & 0xff) / 255., (color & 0xff) / 255., ((color >> 24) & 0xff) / 255.};
    }
    const bool created = create_view(self, text(arguments, "url"), background, &reason);
    fl_value_set_string_take(result, "ok", fl_value_new_bool(created));
    if (!created) fl_value_set_string_take(result, "reason", fl_value_new_string(reason.c_str()));
  } else if (method == "load") {
    const auto uri = text(arguments, "url");
    if (self->web_view != nullptr && g_str_has_prefix(uri.c_str(), "http://127.0.0.1:")) self->api.view_load_uri(self->web_view, uri.c_str());
  } else if (method == "setBounds") {
    self->bounds.x = static_cast<int>(std::lround(number(arguments, "x")));
    self->bounds.y = static_cast<int>(std::lround(number(arguments, "y")));
    self->bounds.width = MAX(1, static_cast<int>(std::lround(number(arguments, "width"))));
    self->bounds.height = MAX(1, static_cast<int>(std::lround(number(arguments, "height"))));
    if (self->web_view != nullptr) gtk_widget_queue_resize(GTK_WIDGET(self->overlay));
  } else if (method == "setVisible") {
    if (self->web_view != nullptr) {
      if (boolean(arguments, "visible")) {
        gtk_widget_show(self->web_view);
      } else {
        gtk_widget_hide(self->web_view);
        give_focus_back(self);
      }
    }
  } else if (method == "destroy") {
    destroy_view(self);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  fl_method_call_respond_success(call, result, nullptr);
}

LyricsView* lyrics_view_new(FlView* view, GtkOverlay* overlay) {
  auto* self = new LyricsView();
  self->flutter_view = view;
  self->overlay = overlay;
  g_signal_connect(overlay, "get-child-position", G_CALLBACK(child_position), self);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(fl_engine_get_binary_messenger(fl_view_get_engine(view)), "top.nekoh2o/lyrics_view", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, channel_call, self, nullptr);
  return self;
}

void lyrics_view_free(LyricsView* self) {
  if (self == nullptr) return;
  fl_method_channel_set_method_call_handler(self->channel, nullptr, nullptr, nullptr);
  g_signal_handlers_disconnect_by_data(self->overlay, self);
  destroy_view(self);
  g_clear_object(&self->channel);
  // The WebKit library stays mapped: its worker processes and GLib types
  // cannot be unloaded safely.
  delete self;
}
