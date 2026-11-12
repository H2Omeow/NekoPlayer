#include "flutter_window.h"

#include <cstdio>
#include <cwchar>
#include <optional>

#include "crash_handler.h"
#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr wchar_t kAccessibilityOverride[] =
    L"NEKOPLAYER_ENABLE_ACCESSIBILITY";
constexpr DWORD kAccessibilityOverrideSize = 16;
constexpr DWORD kUiaRootObjectId = static_cast<DWORD>(-25);
constexpr DWORD kClientObjectId = 0xFFFFFFFCu;

WNDPROC g_original_view_proc = nullptr;

bool AccessibilityRequestedByOverride() {
  wchar_t value[kAccessibilityOverrideSize] = {};
  const DWORD length = ::GetEnvironmentVariableW(
      kAccessibilityOverride, value, kAccessibilityOverrideSize);
  return length > 0 && length < kAccessibilityOverrideSize &&
         (std::wcscmp(value, L"1") == 0 ||
          std::wcscmp(value, L"true") == 0 ||
          std::wcscmp(value, L"yes") == 0);
}

// Flutter enables its accessibility bridge when Windows asks for the UIA root
// object or the MSAA client object. Flutter 3.47.7 then dereferences a null
// AXNode parent in AccessibilityBridge::CreateRemoveReparentedNodesUpdate
// (flutter/flutter#175041). Until that engine bug is fixed, answer those two
// requests with "no accessible object" so the bridge is never created.
bool IsAccessibilityRequest(UINT message, LPARAM lparam) {
  if (message != WM_GETOBJECT) return false;
  const DWORD object_id = static_cast<DWORD>(static_cast<DWORD_PTR>(lparam));
  return object_id == kUiaRootObjectId || object_id == kClientObjectId;
}

LRESULT CALLBACK FilterAccessibilityRequests(HWND window,
                                             UINT message,
                                             WPARAM wparam,
                                             LPARAM lparam) {
  if (IsAccessibilityRequest(message, lparam)) return 0;
  if (g_original_view_proc == nullptr) {
    return ::DefWindowProcW(window, message, wparam, lparam);
  }
  return ::CallWindowProcW(g_original_view_proc, window, message, wparam,
                           lparam);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  if (AccessibilityRequestedByOverride()) {
    std::fprintf(stderr,
                 "[a11y] Windows accessibility bridge enabled by "
                 "NEKOPLAYER_ENABLE_ACCESSIBILITY\n");
  } else {
    filtered_view_ = flutter_controller_->view()->GetNativeWindow();
    original_view_proc_ = reinterpret_cast<WNDPROC>(::SetWindowLongPtrW(
        filtered_view_, GWLP_WNDPROC,
        reinterpret_cast<LONG_PTR>(FilterAccessibilityRequests)));
    if (original_view_proc_ == nullptr) {
      filtered_view_ = nullptr;
      std::fprintf(stderr,
                   "[a11y] failed to install the Windows accessibility "
                   "filter\n");
    } else {
      g_original_view_proc = original_view_proc_;
      std::fprintf(stderr,
                   "[a11y] Windows accessibility bridge disabled to avoid a "
                   "Flutter engine crash; set NEKOPLAYER_ENABLE_ACCESSIBILITY=1 "
                   "to enable it\n");
    }
  }
  std::fflush(stderr);

  desktop_integration_ = std::make_unique<DesktopIntegration>(flutter_controller_->engine()->messenger(), GetHandle());
  lyrics_view_ = std::make_unique<LyricsView>(flutter_controller_->engine()->messenger(), GetHandle(), flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (filtered_view_ != nullptr && original_view_proc_ != nullptr) {
    ::SetWindowLongPtrW(filtered_view_, GWLP_WNDPROC,
                        reinterpret_cast<LONG_PTR>(original_view_proc_));
    g_original_view_proc = nullptr;
    filtered_view_ = nullptr;
    original_view_proc_ = nullptr;
  }
  lyrics_view_.reset();
  desktop_integration_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
  crash_handler::MarkCleanExit();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  try {
    return HandleMessageUnguarded(hwnd, message, wparam, lparam);
  } catch (...) {
    crash_handler::LogCaughtException("FlutterWindow::MessageHandler");
    return ::DefWindowProc(hwnd, message, wparam, lparam);
  }
}

LRESULT FlutterWindow::HandleMessageUnguarded(HWND hwnd, UINT const message,
                                              WPARAM const wparam,
                                              LPARAM const lparam) {
  if (desktop_integration_ && desktop_integration_->HandleMessage(message, wparam, lparam)) return 0;
  if (lyrics_view_) lyrics_view_->HandleMessage(message, wparam, lparam);
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
