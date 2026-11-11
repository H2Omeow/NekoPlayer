#include "lyrics_view.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shlobj.h>

#include <cmath>
#include <cstdio>
#include <string>
#include <utility>

#ifndef NEKO_NO_WEBVIEW2
#include <wrl.h>
#include <WebView2.h>
#endif

using flutter::EncodableMap;
using flutter::EncodableValue;

namespace {
const EncodableValue* Find(const EncodableMap& values, const char* key) {
  const auto found = values.find(EncodableValue(key));
  return found == values.end() ? nullptr : &found->second;
}

std::string Text(const EncodableMap& values, const char* key) {
  const auto* value = Find(values, key);
  const auto* text = value == nullptr ? nullptr : std::get_if<std::string>(value);
  return text == nullptr ? "" : *text;
}

double Number(const EncodableMap& values, const char* key) {
  const auto* value = Find(values, key);
  if (value == nullptr) return 0;
  if (const auto* number = std::get_if<double>(value)) return *number;
  if (const auto* number = std::get_if<int64_t>(value)) return static_cast<double>(*number);
  if (const auto* number = std::get_if<int32_t>(value)) return *number;
  return 0;
}

bool Boolean(const EncodableMap& values, const char* key) {
  const auto* value = Find(values, key);
  const auto* boolean = value == nullptr ? nullptr : std::get_if<bool>(value);
  return boolean != nullptr && *boolean;
}

std::wstring Wide(const std::string& value) {
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(length, L'\0');
  if (length > 0) MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), result.data(), length);
  return result;
}

bool IsLocalPage(const std::wstring& uri) {
  return uri.rfind(L"http://127.0.0.1:", 0) == 0;
}

using MethodResultPtr = std::shared_ptr<flutter::MethodResult<EncodableValue>>;

EncodableValue Outcome(bool ok, const std::string& reason) {
  EncodableMap values{{EncodableValue("ok"), EncodableValue(ok)}};
  if (!ok) values[EncodableValue("reason")] = EncodableValue(reason);
  return EncodableValue(values);
}
}  // namespace

#ifdef NEKO_NO_WEBVIEW2

struct LyricsView::State {
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
};

LyricsView::LyricsView(flutter::BinaryMessenger* messenger, HWND, HWND) : state_(std::make_shared<State>()) {
  state_->channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(messenger, "top.nekoh2o/lyrics_view", &flutter::StandardMethodCodec::GetInstance());
  state_->channel->SetMethodCallHandler([](const auto& call, auto result) {
    const std::string reason = "此版本未包含 WebView2 组件";
    if (call.method_name() == "isAvailable") {
      result->Success(EncodableValue(EncodableMap{{EncodableValue("available"), EncodableValue(false)}, {EncodableValue("reason"), EncodableValue(reason)}}));
    } else if (call.method_name() == "create") {
      result->Success(Outcome(false, reason));
    } else {
      result->Success(EncodableValue(EncodableMap{}));
    }
  });
}

LyricsView::~LyricsView() { state_->channel->SetMethodCallHandler(nullptr); }

void LyricsView::HandleMessage(UINT, WPARAM, LPARAM) {}

#else

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

struct LyricsView::State : std::enable_shared_from_this<LyricsView::State> {
  HWND window = nullptr;
  HWND flutter_view = nullptr;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
  ComPtr<ICoreWebView2Environment> environment;
  ComPtr<ICoreWebView2Controller> controller;
  ComPtr<ICoreWebView2> webview;
  EventRegistrationToken navigation_starting{};
  EventRegistrationToken navigation_completed{};
  EventRegistrationToken process_failed{};
  EventRegistrationToken new_window{};
  MethodResultPtr pending;
  unsigned long long generation = 0;
  RECT bounds{0, 0, 1, 1};
  double rasterization_scale = 1;
  bool visible = false;
  COREWEBVIEW2_COLOR background{0xff, 0x14, 0x13, 0x1b};
  std::wstring url;

  static bool Available(std::string* reason) {
    LPWSTR version = nullptr;
    const HRESULT result = GetAvailableCoreWebView2BrowserVersionString(nullptr, &version);
    const bool found = SUCCEEDED(result) && version != nullptr && version[0] != L'\0';
    if (version != nullptr) CoTaskMemFree(version);
    if (!found) *reason = "未安装 Microsoft Edge WebView2 运行时（Windows 11 已内置，Windows 10 可从微软官网安装）";
    return found;
  }

  static std::wstring UserDataFolder() {
    PWSTR root = nullptr;
    std::wstring folder;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_CREATE, nullptr, &root)) && root != nullptr) {
      folder = std::wstring(root) + L"\\NekoPlayer\\WebView2";
      SHCreateDirectoryExW(nullptr, folder.c_str(), nullptr);
    }
    if (root != nullptr) CoTaskMemFree(root);
    return folder;
  }

  void Emit(const char* type, const std::string& message) {
    channel->InvokeMethod("event", std::make_unique<EncodableValue>(EncodableMap{{EncodableValue("type"), EncodableValue(type)}, {EncodableValue("message"), EncodableValue(message)}}));
  }

  void Resolve(bool ok, const std::string& reason) {
    if (!pending) return;
    auto result = std::move(pending);
    pending = nullptr;
    result->Success(Outcome(ok, reason));
  }

  void Create(const std::string& uri, const COREWEBVIEW2_COLOR& color, MethodResultPtr result) {
    Destroy();
    std::string reason;
    url = Wide(uri);
    if (!IsLocalPage(url)) {
      result->Success(Outcome(false, "只允许加载本机动态歌词页面"));
      return;
    }
    if (!Available(&reason)) {
      result->Success(Outcome(false, reason));
      return;
    }
    background = color;
    pending = std::move(result);
    const auto id = ++generation;
    if (environment) {
      CreateController(id);
      return;
    }
    std::weak_ptr<State> weak = shared_from_this();
    const std::wstring data_folder = UserDataFolder();
    const HRESULT started = CreateCoreWebView2EnvironmentWithOptions(
        nullptr, data_folder.empty() ? nullptr : data_folder.c_str(), nullptr,
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
            [weak, id](HRESULT error, ICoreWebView2Environment* created) -> HRESULT {
              auto self = weak.lock();
              if (!self || self->generation != id) return S_OK;
              if (FAILED(error) || created == nullptr) {
                self->Resolve(false, "无法初始化 WebView2 环境（0x" + Hex(error) + "）");
                return S_OK;
              }
              self->environment = created;
              self->CreateController(id);
              return S_OK;
            }).Get());
    if (FAILED(started)) Resolve(false, "无法启动 WebView2（0x" + Hex(started) + "）");
  }

  static std::string Hex(HRESULT value) {
    char text[16];
    snprintf(text, sizeof(text), "%08lX", static_cast<unsigned long>(value));
    return text;
  }

  void CreateController(unsigned long long id) {
    std::weak_ptr<State> weak = shared_from_this();
    const HRESULT started = environment->CreateCoreWebView2Controller(
        window,
        Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
            [weak, id](HRESULT error, ICoreWebView2Controller* created) -> HRESULT {
              auto self = weak.lock();
              if (!self || self->generation != id) {
                if (created != nullptr) created->Close();
                return S_OK;
              }
              if (FAILED(error) || created == nullptr) {
                self->Resolve(false, "无法创建 WebView2 视图（0x" + Hex(error) + "）");
                return S_OK;
              }
              self->Attach(created);
              return S_OK;
            }).Get());
    if (FAILED(started)) Resolve(false, "无法创建 WebView2 视图（0x" + Hex(started) + "）");
  }

  void Attach(ICoreWebView2Controller* created) {
    controller = created;
    if (FAILED(controller->get_CoreWebView2(&webview)) || !webview) {
      auto result = std::move(pending);
      pending = nullptr;
      Destroy();
      if (result) result->Success(Outcome(false, "无法获取 WebView2 内核"));
      return;
    }
    // Bounds are supplied in physical pixels by the Flutter runner. Keep the
    // WebView2 coordinate policy deterministic so 300% Windows scaling cannot
    // apply the DPI factor a second time and leave the page off-screen.
    ComPtr<ICoreWebView2Controller3> modern;
    if (SUCCEEDED(controller.As(&modern)) && modern) {
      modern->put_BoundsMode(COREWEBVIEW2_BOUNDS_MODE_USE_RAW_PIXELS);
      modern->put_ShouldDetectMonitorScaleChanges(FALSE);
      modern->put_RasterizationScale(rasterization_scale);
    }
    controller->put_Bounds(bounds);
    controller->put_IsVisible(visible ? TRUE : FALSE);
    ComPtr<ICoreWebView2Controller2> colored;
    if (SUCCEEDED(controller.As(&colored))) colored->put_DefaultBackgroundColor(background);
    ComPtr<ICoreWebView2Settings> settings;
    if (SUCCEEDED(webview->get_Settings(&settings)) && settings) {
      settings->put_AreDefaultContextMenusEnabled(FALSE);
      settings->put_IsStatusBarEnabled(FALSE);
      settings->put_IsZoomControlEnabled(FALSE);
      settings->put_AreDevToolsEnabled(GetEnvironmentVariableW(L"NEKOPLAYER_LYRICS_DEBUG", nullptr, 0) > 0 ? TRUE : FALSE);
      ComPtr<ICoreWebView2Settings3> keys;
      if (SUCCEEDED(settings.As(&keys))) keys->put_AreBrowserAcceleratorKeysEnabled(FALSE);
    }
    std::weak_ptr<State> weak = shared_from_this();
    webview->add_NavigationStarting(
        Callback<ICoreWebView2NavigationStartingEventHandler>(
            [](ICoreWebView2*, ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT {
              LPWSTR uri = nullptr;
              if (SUCCEEDED(args->get_Uri(&uri)) && uri != nullptr) {
                if (!IsLocalPage(uri)) args->put_Cancel(TRUE);
                CoTaskMemFree(uri);
              }
              return S_OK;
            }).Get(),
        &navigation_starting);
    webview->add_NavigationCompleted(
        Callback<ICoreWebView2NavigationCompletedEventHandler>(
            [weak](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
              auto self = weak.lock();
              BOOL success = TRUE;
              if (!self || FAILED(args->get_IsSuccess(&success)) || success) return S_OK;
              COREWEBVIEW2_WEB_ERROR_STATUS status = COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN;
              args->get_WebErrorStatus(&status);
              self->Emit("loadFailed", "WebView2 错误代码 " + std::to_string(static_cast<int>(status)));
              return S_OK;
            }).Get(),
        &navigation_completed);
    webview->add_ProcessFailed(
        Callback<ICoreWebView2ProcessFailedEventHandler>(
            [weak](ICoreWebView2*, ICoreWebView2ProcessFailedEventArgs* args) -> HRESULT {
              auto self = weak.lock();
              COREWEBVIEW2_PROCESS_FAILED_KIND kind = COREWEBVIEW2_PROCESS_FAILED_KIND_BROWSER_PROCESS_EXITED;
              if (!self || FAILED(args->get_ProcessFailedKind(&kind))) return S_OK;
              if (kind == COREWEBVIEW2_PROCESS_FAILED_KIND_BROWSER_PROCESS_EXITED || kind == COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_EXITED) {
                self->Emit("crashed", "动态歌词渲染进程已退出");
              }
              return S_OK;
            }).Get(),
        &process_failed);
    webview->add_NewWindowRequested(
        Callback<ICoreWebView2NewWindowRequestedEventHandler>(
            [](ICoreWebView2*, ICoreWebView2NewWindowRequestedEventArgs* args) -> HRESULT {
              args->put_Handled(TRUE);
              return S_OK;
            }).Get(),
        &new_window);
    const HRESULT navigated = webview->Navigate(url.c_str());
    if (FAILED(navigated)) {
      auto result = std::move(pending);
      pending = nullptr;
      Destroy();
      if (result) result->Success(Outcome(false, "无法打开动态歌词页面（0x" + Hex(navigated) + "）"));
      return;
    }
    Resolve(true, "");
  }

  void Destroy() {
    ++generation;
    Resolve(false, "已取消");
    if (webview) {
      webview->remove_NavigationStarting(navigation_starting);
      webview->remove_NavigationCompleted(navigation_completed);
      webview->remove_ProcessFailed(process_failed);
      webview->remove_NewWindowRequested(new_window);
    }
    const bool had_view = controller != nullptr;
    if (controller) controller->Close();
    controller.Reset();
    webview.Reset();
    visible = false;
    if (had_view && IsWindow(flutter_view)) SetFocus(flutter_view);
  }

  // Logical pixels relative to the Flutter view, which fills the client area.
  void SetBounds(double x, double y, double width, double height, double ratio) {
    if (!(ratio > 0)) ratio = 1;
    rasterization_scale = ratio;
    bounds.left = static_cast<LONG>(std::lround(x * ratio));
    bounds.top = static_cast<LONG>(std::lround(y * ratio));
    bounds.right = static_cast<LONG>(std::lround((x + width) * ratio));
    bounds.bottom = static_cast<LONG>(std::lround((y + height) * ratio));
    if (!controller) return;
    ComPtr<ICoreWebView2Controller3> modern;
    if (SUCCEEDED(controller.As(&modern)) && modern) {
      // Raw physical bounds + an explicit rasterization scale keep the CSS
      // viewport equal to the Flutter logical size at every DPI.
      modern->put_RasterizationScale(rasterization_scale);
    }
    controller->put_Bounds(bounds);
  }

  void SetVisible(bool value) {
    visible = value;
    if (!controller) return;
    controller->put_IsVisible(value ? TRUE : FALSE);
    if (!value && IsWindow(flutter_view)) SetFocus(flutter_view);
  }

  void Handle(const flutter::MethodCall<EncodableValue>& call, MethodResultPtr result) {
    const auto* values = call.arguments() == nullptr ? nullptr : std::get_if<EncodableMap>(call.arguments());
    const EncodableMap none;
    const EncodableMap& arguments = values == nullptr ? none : *values;
    const auto& method = call.method_name();
    if (method == "isAvailable") {
      std::string reason;
      const bool available = Available(&reason);
      EncodableMap response{{EncodableValue("available"), EncodableValue(available)}};
      if (!available) response[EncodableValue("reason")] = EncodableValue(reason);
      result->Success(EncodableValue(response));
    } else if (method == "create") {
      COREWEBVIEW2_COLOR color = background;
      if (Find(arguments, "background") != nullptr) {
        const auto argb = static_cast<unsigned int>(static_cast<long long>(Number(arguments, "background")));
        color = {static_cast<BYTE>(argb >> 24), static_cast<BYTE>(argb >> 16), static_cast<BYTE>(argb >> 8), static_cast<BYTE>(argb)};
      }
      Create(Text(arguments, "url"), color, std::move(result));
    } else if (method == "load") {
      const std::wstring uri = Wide(Text(arguments, "url"));
      if (webview && IsLocalPage(uri)) webview->Navigate(uri.c_str());
      result->Success(EncodableValue(EncodableMap{}));
    } else if (method == "setBounds") {
      SetBounds(Number(arguments, "x"), Number(arguments, "y"), Number(arguments, "width"), Number(arguments, "height"), Number(arguments, "devicePixelRatio"));
      result->Success(EncodableValue(EncodableMap{}));
    } else if (method == "setVisible") {
      SetVisible(Boolean(arguments, "visible"));
      result->Success(EncodableValue(EncodableMap{}));
    } else if (method == "destroy") {
      Destroy();
      result->Success(EncodableValue(EncodableMap{}));
    } else {
      result->NotImplemented();
    }
  }
};

LyricsView::LyricsView(flutter::BinaryMessenger* messenger, HWND window, HWND flutter_view) : state_(std::make_shared<State>()) {
  state_->window = window;
  state_->flutter_view = flutter_view;
  state_->channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(messenger, "top.nekoh2o/lyrics_view", &flutter::StandardMethodCodec::GetInstance());
  std::weak_ptr<State> weak = state_;
  state_->channel->SetMethodCallHandler([weak](const auto& call, auto result) {
    if (auto state = weak.lock()) state->Handle(call, MethodResultPtr(std::move(result)));
  });
}

LyricsView::~LyricsView() {
  state_->channel->SetMethodCallHandler(nullptr);
  state_->Destroy();
}

void LyricsView::HandleMessage(UINT message, WPARAM, LPARAM) {
  if ((message == WM_MOVE || message == WM_MOVING) && state_->controller) state_->controller->NotifyParentWindowPositionChanged();
}

#endif
