#include "flutter_window.h"

#include <atomic>
#include <cstdio>
#include <cwchar>
#include <optional>

#include "crash_handler.h"
#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr wchar_t kAccessibilityOverride[] =
    L"NEKOPLAYER_ENABLE_ACCESSIBILITY";
constexpr DWORD kAccessibilityOverrideSize = 16;
constexpr wchar_t kOriginalProcProperty[] = L"NekoPlayerOriginalProc";
constexpr wchar_t kFlutterViewClass[] = L"FLUTTERVIEW";

WNDPROC g_original_view_proc = nullptr;
HWND g_filtered_view = nullptr;
HHOOK g_create_hook = nullptr;
bool g_block_accessibility = false;
std::atomic<int> g_blocked_requests{0};

bool AccessibilityRequestedByOverride() {
  wchar_t value[kAccessibilityOverrideSize] = {};
  const DWORD length = ::GetEnvironmentVariableW(
      kAccessibilityOverride, value, kAccessibilityOverrideSize);
  return length > 0 && length < kAccessibilityOverrideSize &&
         (std::wcscmp(value, L"1") == 0 ||
          std::wcscmp(value, L"true") == 0 ||
          std::wcscmp(value, L"yes") == 0);
}

void LogAccessibility(const char* message) {
  crash_handler::LogNative(message);
  ::OutputDebugStringA(message);
  ::OutputDebugStringA("\n");
  std::fprintf(stderr, "%s\n", message);
  std::fflush(stderr);
}

void LogBlockedRequest(HWND window, LPARAM lparam) {
  if (g_blocked_requests.fetch_add(1) >= 20) return;
  char text[192];
  std::snprintf(text, sizeof(text),
                "a11y: blocked WM_GETOBJECT object=0x%08lX window=%p",
                static_cast<unsigned long>(
                    static_cast<DWORD>(static_cast<DWORD_PTR>(lparam))),
                reinterpret_cast<void*>(window));
  LogAccessibility(text);
}

// Flutter 3.47.7 enables its accessibility bridge when a UIA or MSAA client
// asks for the view's accessible object and then dereferences a null AXNode
// parent in AccessibilityBridge::CreateRemoveReparentedNodesUpdate
// (flutter/flutter#175041). Until that engine bug is fixed, answer every
// accessibility request with "no accessible object" so the bridge is never
// created.
LRESULT CALLBACK FilterAccessibilityRequests(HWND window,
                                             UINT message,
                                             WPARAM wparam,
                                             LPARAM lparam) {
  if (message == WM_GETOBJECT) {
    LogBlockedRequest(window, lparam);
    return 0;
  }
  WNDPROC original = reinterpret_cast<WNDPROC>(
      ::GetPropW(window, kOriginalProcProperty));
  if (original == nullptr) original = g_original_view_proc;
  if (original == nullptr) {
    return ::DefWindowProcW(window, message, wparam, lparam);
  }
  return ::CallWindowProcW(original, window, message, wparam, lparam);
}

bool InstallViewFilter(HWND window) {
  if (window == nullptr) return false;
  if (::GetWindowThreadProcessId(window, nullptr) != ::GetCurrentThreadId()) {
    return false;
  }
  WNDPROC original = reinterpret_cast<WNDPROC>(
      ::GetWindowLongPtrW(window, GWLP_WNDPROC));
  if (original == nullptr) {
    original = reinterpret_cast<WNDPROC>(
        ::GetClassLongPtrW(window, GCLP_WNDPROC));
  }
  if (original == nullptr || original == FilterAccessibilityRequests) {
    return false;
  }
  if (::SetPropW(window, kOriginalProcProperty,
                 reinterpret_cast<HANDLE>(original)) == FALSE) {
    return false;
  }
  ::SetLastError(0);
  const LONG_PTR previous = ::SetWindowLongPtrW(
      window, GWLP_WNDPROC,
      reinterpret_cast<LONG_PTR>(FilterAccessibilityRequests));
  if (previous == 0 && ::GetLastError() != 0) {
    ::RemovePropW(window, kOriginalProcProperty);
    return false;
  }
  if (g_original_view_proc == nullptr) g_original_view_proc = original;
  g_filtered_view = window;
  return true;
}

// Install the filter while the engine creates its "FLUTTERVIEW" window. The
// engine can be asked for accessibility as soon as the HWND exists, so a
// filter installed after FlutterViewController construction can lose the race
// and leave the bridge enabled for the rest of the session.
LRESULT CALLBACK AccessibilityCreateHook(int code, WPARAM wparam,
                                         LPARAM lparam) {
  if (code == HCBT_CREATEWND) {
    const auto* create = reinterpret_cast<const CBT_CREATEWNDW*>(lparam);
    const wchar_t* class_name =
        create != nullptr && create->lpcs != nullptr
            ? create->lpcs->lpszClass
            : nullptr;
    if (class_name != nullptr &&
        (reinterpret_cast<ULONG_PTR>(class_name) >> 16) != 0 &&
        std::wcscmp(class_name, kFlutterViewClass) == 0) {
      InstallViewFilter(reinterpret_cast<HWND>(wparam));
    }
  }
  return ::CallNextHookEx(g_create_hook, code, wparam, lparam);
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
  const bool allow_accessibility = AccessibilityRequestedByOverride();
  g_block_accessibility = !allow_accessibility;
  if (allow_accessibility) {
    LogAccessibility(
        "a11y: Windows accessibility bridge enabled by "
        "NEKOPLAYER_ENABLE_ACCESSIBILITY");
  } else {
    g_create_hook = ::SetWindowsHookExW(
        WH_CBT, AccessibilityCreateHook, ::GetModuleHandleW(nullptr),
        ::GetCurrentThreadId());
    if (g_create_hook == nullptr) {
      LogAccessibility("a11y: failed to install the window creation hook");
    }
  }

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    if (g_create_hook != nullptr) {
      ::UnhookWindowsHookEx(g_create_hook);
      g_create_hook = nullptr;
    }
    return false;
  }

  HWND view = flutter_controller_->view()->GetNativeWindow();
  if (!allow_accessibility) {
    const WNDPROC current = reinterpret_cast<WNDPROC>(
        ::GetWindowLongPtrW(view, GWLP_WNDPROC));
    const bool early = current == FilterAccessibilityRequests;
    if (!early && !InstallViewFilter(view)) {
      LogAccessibility(
          "a11y: failed to install the Windows accessibility filter");
    } else {
      char text[224];
      std::snprintf(text, sizeof(text),
                    "a11y: Windows accessibility bridge disabled to avoid a "
                    "Flutter engine crash; view=%p filter=%s (set "
                    "NEKOPLAYER_ENABLE_ACCESSIBILITY=1 to enable it)",
                    reinterpret_cast<void*>(view), early ? "early" : "late");
      LogAccessibility(text);
    }
  }

  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(view);

  desktop_integration_ = std::make_unique<DesktopIntegration>(flutter_controller_->engine()->messenger(), GetHandle());
  lyrics_view_ = std::make_unique<LyricsView>(flutter_controller_->engine()->messenger(), GetHandle(), view);

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
  if (g_create_hook != nullptr) {
    ::UnhookWindowsHookEx(g_create_hook);
    g_create_hook = nullptr;
  }
  g_filtered_view = nullptr;
  g_original_view_proc = nullptr;
  g_block_accessibility = false;
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
  if (g_block_accessibility && message == WM_GETOBJECT) {
    LogBlockedRequest(hwnd, lparam);
    return 0;
  }
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
