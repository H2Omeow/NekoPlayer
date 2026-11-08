#include "flutter_window.h"

#include <optional>

#include "crash_handler.h"
#include "flutter/generated_plugin_registrant.h"

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
