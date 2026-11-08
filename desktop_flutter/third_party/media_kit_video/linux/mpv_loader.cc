// Runtime libmpv binding for the Linux video plugin.
//
// The upstream plugin links libmpv at build time, which records a hard
// DT_NEEDED on the soname of the build machine (libmpv.so.1 on Ubuntu 22.04).
// Distributions that only ship libmpv.so.2 then fail to load the plugin.
// The client and render APIs used here are ABI-compatible across both
// sonames, so the symbols are resolved lazily instead.

#include <dlfcn.h>
#include <stdlib.h>

#include <initializer_list>
#include <mutex>

#include "mpv/client.h"
#include "mpv/render.h"

namespace {

// Prefers a libmpv that media_kit's Dart side already loaded, so the render
// context is always created by the same library that owns the mpv_handle.
void* LoadLibmpv() {
  const char* override_path = getenv("LIBMPV_LIBRARY_PATH");
  const char* names[] = {override_path, "libmpv.so.2", "libmpv.so.1",
                         "libmpv.so"};
  for (int flags : {RTLD_NOW | RTLD_NOLOAD, RTLD_NOW | RTLD_LOCAL}) {
    for (const char* name : names) {
      if (name == nullptr || name[0] == '\0') continue;
      if (void* handle = dlopen(name, flags)) return handle;
    }
  }
  return nullptr;
}

void* Resolve(const char* symbol) {
  static void* library = nullptr;
  static std::once_flag once;
  std::call_once(once, [] { library = LoadLibmpv(); });
  return library != nullptr ? dlsym(library, symbol) : nullptr;
}

template <typename Fn>
Fn Lookup(const char* symbol) {
  return reinterpret_cast<Fn>(Resolve(symbol));
}

}  // namespace

extern "C" {

int mpv_set_option_string(mpv_handle* ctx, const char* name, const char* data) {
  static auto fn = Lookup<int (*)(mpv_handle*, const char*, const char*)>(
      "mpv_set_option_string");
  return fn != nullptr ? fn(ctx, name, data) : MPV_ERROR_UNSUPPORTED;
}

int mpv_get_property(mpv_handle* ctx, const char* name, mpv_format format,
                     void* data) {
  static auto fn =
      Lookup<int (*)(mpv_handle*, const char*, mpv_format, void*)>(
          "mpv_get_property");
  return fn != nullptr ? fn(ctx, name, format, data) : MPV_ERROR_UNSUPPORTED;
}

void mpv_free_node_contents(mpv_node* node) {
  static auto fn = Lookup<void (*)(mpv_node*)>("mpv_free_node_contents");
  if (fn != nullptr) fn(node);
}

int mpv_render_context_create(mpv_render_context** res, mpv_handle* mpv,
                              mpv_render_param* params) {
  static auto fn = Lookup<int (*)(mpv_render_context**, mpv_handle*,
                                  mpv_render_param*)>(
      "mpv_render_context_create");
  return fn != nullptr ? fn(res, mpv, params) : MPV_ERROR_UNSUPPORTED;
}

void mpv_render_context_set_update_callback(mpv_render_context* ctx,
                                            mpv_render_update_fn callback,
                                            void* callback_ctx) {
  static auto fn =
      Lookup<void (*)(mpv_render_context*, mpv_render_update_fn, void*)>(
          "mpv_render_context_set_update_callback");
  if (fn != nullptr) fn(ctx, callback, callback_ctx);
}

int mpv_render_context_render(mpv_render_context* ctx,
                              mpv_render_param* params) {
  static auto fn = Lookup<int (*)(mpv_render_context*, mpv_render_param*)>(
      "mpv_render_context_render");
  return fn != nullptr ? fn(ctx, params) : MPV_ERROR_UNSUPPORTED;
}

void mpv_render_context_free(mpv_render_context* ctx) {
  static auto fn = Lookup<void (*)(mpv_render_context*)>(
      "mpv_render_context_free");
  if (fn != nullptr) fn(ctx);
}

}  // extern "C"
