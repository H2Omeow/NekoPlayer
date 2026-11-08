#include "desktop_integration.h"
#include "resource.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <SystemMediaTransportControlsInterop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/base.h>
#include <shellapi.h>

#include <algorithm>
#include <cmath>
#include <memory>
#include <string>

using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Media::MediaPlaybackStatus;
using winrt::Windows::Media::SystemMediaTransportControls;
using winrt::Windows::Media::SystemMediaTransportControlsButton;

namespace {
constexpr UINT kMediaAction = WM_APP + 47;
constexpr UINT kTrayAction = WM_APP + 48;
constexpr UINT kMediaSetting = WM_APP + 49;
constexpr wchar_t kLyricsClass[] = L"NekoPlayerFlutterLyrics";

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
}

struct DesktopIntegration::State {
  HWND main_window;
  HWND lyrics_window = nullptr;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
  SystemMediaTransportControls controls{nullptr};
  winrt::event_token button_token{};
  winrt::event_token position_token{};
  winrt::event_token rate_token{};
  winrt::event_token loop_token{};
  winrt::event_token shuffle_token{};
  std::wstring lyric;
  std::wstring next_lyric;
  int font_size = 30;
  bool locked = false;
  bool visible = false;
  std::string metadata_key;
  NOTIFYICONDATAW tray{};
  UINT taskbar_created = RegisterWindowMessageW(L"TaskbarCreated");
  bool tray_available = false;
  // True between Dart "initialize" and "dispose"; gates tray re-creation.
  bool tray_enabled = false;
  // Outlives State so a nested modal loop can detect that State was destroyed.
  std::shared_ptr<bool> alive = std::make_shared<bool>(true);
  bool close_to_tray = false;
  bool quitting = false;

  void ShowMain() {
    ShowWindow(main_window, IsIconic(main_window) ? SW_RESTORE : SW_SHOW);
    SetForegroundWindow(main_window);
  }

  void StartTray() {
    tray_enabled = true;
    if (tray_available) return;
    tray = {};
    tray.cbSize = sizeof(tray);
    tray.hWnd = main_window;
    tray.uID = 1;
    tray.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    tray.uCallbackMessage = kTrayAction;
    tray.hIcon = LoadIconW(GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
    wcscpy_s(tray.szTip, L"NekoPlayer — 点击显示播放器");
    tray_available = Shell_NotifyIconW(NIM_ADD, &tray) != FALSE;
    if (tray_available) {
      tray.uVersion = NOTIFYICON_VERSION_4;
      if (!Shell_NotifyIconW(NIM_SETVERSION, &tray)) {
        Shell_NotifyIconW(NIM_DELETE, &tray);
        tray_available = false;
      }
    }
  }

  void TrayChanged() {
    if (!tray_available) {
      close_to_tray = false;
      if (!IsWindowVisible(main_window)) ShowMain();
    }
    channel->InvokeMethod("trayChanged", std::make_unique<EncodableValue>(EncodableMap{{EncodableValue("available"), EncodableValue(tray_available)}}));
  }

  void TrayMenu() {
    const HMENU menu = CreatePopupMenu();
    if (menu == nullptr) return;
    AppendMenuW(menu, MF_STRING, 1, L"显示播放器");
    AppendMenuW(menu, MF_STRING, 2, L"播放 / 暂停");
    AppendMenuW(menu, MF_STRING, 3, L"上一首");
    AppendMenuW(menu, MF_STRING, 4, L"下一首");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, 5, L"退出");
    POINT location{};
    GetCursorPos(&location);
    SetForegroundWindow(main_window);
    // TrackPopupMenu runs a nested message loop that can destroy this State
    // (window closed, Dart dispose); only locals may be used if that happened.
    const std::shared_ptr<bool> still_alive = alive;
    const HWND window = main_window;
    const int command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON, location.x, location.y, 0, window, nullptr);
    DestroyMenu(menu);
    PostMessage(window, WM_NULL, 0, 0);
    if (!*still_alive) return;
    switch (command) {
      case 1: ShowMain(); break;
      case 2: Action("toggle"); break;
      case 3: Action("previous"); break;
      case 4: Action("next"); break;
      case 5: quitting = true; PostMessage(main_window, WM_CLOSE, 0, 0); break;
      default: break;
    }
  }

  void Action(const char* name) {
    channel->InvokeMethod("action", std::make_unique<EncodableValue>(EncodableMap{{EncodableValue("action"), EncodableValue(name)}}));
  }

  void Setting(const char* name, EncodableValue value) {
    channel->InvokeMethod("action", std::make_unique<EncodableValue>(EncodableMap{
        {EncodableValue("action"), EncodableValue(name)}, {EncodableValue("value"), std::move(value)}}));
  }

  void Stop() {
    close_to_tray = false;
    tray_enabled = false;
    if (tray_available) Shell_NotifyIconW(NIM_DELETE, &tray);
    tray_available = false;
    StopMedia();
    if (lyrics_window != nullptr) ShowWindow(lyrics_window, SW_HIDE);
  }

  void StopMedia() {
    if (controls) {
      try {
        controls.ButtonPressed(button_token);
        controls.PlaybackPositionChangeRequested(position_token);
        controls.PlaybackRateChangeRequested(rate_token);
        controls.AutoRepeatModeChangeRequested(loop_token);
        controls.ShuffleEnabledChangeRequested(shuffle_token);
        controls.IsEnabled(false);
        controls.DisplayUpdater().ClearAll();
      } catch (...) {}
      controls = nullptr;
    }
    metadata_key.clear();
    MSG pending{};
    while (PeekMessage(&pending, main_window, kMediaAction, kMediaAction, PM_REMOVE)) {}
    while (PeekMessage(&pending, main_window, kMediaSetting, kMediaSetting, PM_REMOVE)) {}
  }

  bool Initialize() {
    if (controls) return true;
    try {
      const auto interop = winrt::get_activation_factory<SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
      interop->GetForWindow(main_window, winrt::guid_of<SystemMediaTransportControls>(), winrt::put_abi(controls));
      controls.IsEnabled(true);
      controls.IsPlayEnabled(true);
      controls.IsPauseEnabled(true);
      controls.IsStopEnabled(true);
      controls.IsNextEnabled(true);
      controls.IsPreviousEnabled(true);
      const HWND destination = main_window;
      button_token = controls.ButtonPressed([destination](const auto&, const auto& args) {
        PostMessage(destination, kMediaAction, static_cast<WPARAM>(args.Button()), 0);
      });
      position_token = controls.PlaybackPositionChangeRequested([destination](const auto&, const auto& args) {
        const int64_t microseconds = args.RequestedPlaybackPosition().count() / 10;
        if (microseconds >= 0) PostMessage(destination, kMediaSetting, 1, static_cast<LPARAM>(microseconds));
      });
      rate_token = controls.PlaybackRateChangeRequested([destination](const auto&, const auto& args) {
        const double rate = args.RequestedPlaybackRate();
        if (std::isfinite(rate) && rate >= .5 && rate <= 2.) {
          PostMessage(destination, kMediaSetting, 2, static_cast<LPARAM>(std::llround(rate * 10000)));
        }
      });
      loop_token = controls.AutoRepeatModeChangeRequested([destination](const auto&, const auto& args) {
        PostMessage(destination, kMediaSetting, 3, static_cast<LPARAM>(args.RequestedAutoRepeatMode()));
      });
      shuffle_token = controls.ShuffleEnabledChangeRequested([destination](const auto&, const auto& args) {
        PostMessage(destination, kMediaSetting, 4, args.RequestedShuffleEnabled() ? 1 : 0);
      });
      return true;
    } catch (...) { StopMedia(); return false; }
  }

  static LRESULT CALLBACK LyricsProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    auto* self = reinterpret_cast<State*>(GetWindowLongPtr(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
      const auto* creation = reinterpret_cast<CREATESTRUCT*>(lparam);
      self = static_cast<State*>(creation->lpCreateParams);
      SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    if (self == nullptr) return DefWindowProc(window, message, wparam, lparam);
    switch (message) {
      case WM_MOUSEACTIVATE: return MA_NOACTIVATE;
      case WM_NCHITTEST: return self->locked ? HTTRANSPARENT : HTCLIENT;
      case WM_LBUTTONDOWN:
        if (!self->locked) {
          ReleaseCapture();
          SendMessage(window, WM_NCLBUTTONDOWN, HTCAPTION, lparam);
        }
        return 0;
      case WM_LBUTTONDBLCLK: self->Action("toggle"); return 0;
      case WM_CLOSE:
        ShowWindow(window, SW_HIDE);
        self->visible = false;
        self->channel->InvokeMethod("overlayClosed", nullptr);
        return 0;
      case WM_ERASEBKGND: return 1;
      case WM_PAINT: {
        PAINTSTRUCT paint;
        HDC target = BeginPaint(window, &paint);
        RECT area;
        GetClientRect(window, &area);
        HDC buffer = CreateCompatibleDC(target);
        HBITMAP bitmap = CreateCompatibleBitmap(target, area.right, area.bottom);
        const auto old_bitmap = SelectObject(buffer, bitmap);
        HBRUSH background = CreateSolidBrush(RGB(17, 17, 22));
        FillRect(buffer, &area, background);
        DeleteObject(background);
        SetBkMode(buffer, TRANSPARENT);
        const int dpi = GetDpiForWindow(window);
        HFONT primary = CreateFont(-MulDiv(self->font_size, dpi, 96), 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Microsoft YaHei");
        const auto old_font = SelectObject(buffer, primary);
        SetTextColor(buffer, RGB(255, 140, 150));
        RECT first = {12, 8, area.right - 12, area.bottom / 2 + 6};
        DrawText(buffer, self->lyric.c_str(), -1, &first, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
        HFONT secondary = CreateFont(-MulDiv(self->font_size * 2 / 3, dpi, 96), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Microsoft YaHei");
        SelectObject(buffer, secondary);
        SetTextColor(buffer, RGB(202, 194, 220));
        RECT second = {12, area.bottom / 2, area.right - 12, area.bottom - 8};
        DrawText(buffer, self->next_lyric.c_str(), -1, &second, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
        BitBlt(target, 0, 0, area.right, area.bottom, buffer, 0, 0, SRCCOPY);
        SelectObject(buffer, old_font);
        DeleteObject(primary); DeleteObject(secondary);
        SelectObject(buffer, old_bitmap); DeleteObject(bitmap); DeleteDC(buffer);
        EndPaint(window, &paint);
        return 0;
      }
    }
    return DefWindowProc(window, message, wparam, lparam);
  }

  void Lyrics(const EncodableMap& values) {
    visible = Boolean(values, "lyricsVisible");
    if (!visible) { if (lyrics_window != nullptr) ShowWindow(lyrics_window, SW_HIDE); return; }
    if (lyrics_window == nullptr) {
      WNDCLASS registration{};
      registration.lpfnWndProc = LyricsProc;
      registration.hInstance = GetModuleHandle(nullptr);
      registration.lpszClassName = kLyricsClass;
      registration.style = CS_DBLCLKS;
      registration.hCursor = LoadCursor(nullptr, IDC_ARROW);
      RegisterClass(&registration);
      const HMONITOR monitor = MonitorFromWindow(main_window, MONITOR_DEFAULTTONEAREST);
      MONITORINFO info{sizeof(MONITORINFO)};
      GetMonitorInfo(monitor, &info);
      const int width = std::min(760L, info.rcWork.right - info.rcWork.left);
      lyrics_window = CreateWindowEx(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED, kLyricsClass, L"NekoPlayer 桌面歌词", WS_POPUP,
        info.rcWork.left + (info.rcWork.right - info.rcWork.left - width) / 2, info.rcWork.bottom - 180, width, 130, nullptr, nullptr, registration.hInstance, this);
    }
    if (lyrics_window == nullptr) return;
    lyric = Wide(Text(values, "lyric")); next_lyric = Wide(Text(values, "nextLyric"));
    font_size = static_cast<int>(std::clamp(Number(values, "lyricsSize"), 18., 64.));
    locked = Boolean(values, "lyricsLocked");
    LONG_PTR style = GetWindowLongPtr(lyrics_window, GWL_EXSTYLE);
    style = locked ? style | WS_EX_TRANSPARENT : style & ~WS_EX_TRANSPARENT;
    SetWindowLongPtr(lyrics_window, GWL_EXSTYLE, style);
    SetLayeredWindowAttributes(lyrics_window, 0, static_cast<BYTE>(std::clamp(Number(values, "lyricsOpacity"), .25, 1.) * 255), LWA_ALPHA);
    SetWindowPos(lyrics_window, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    InvalidateRect(lyrics_window, nullptr, FALSE);
  }

  void Update(const EncodableMap& values) {
    Lyrics(values);
    if (!controls) return;
    const bool has_track = Boolean(values, "hasTrack");
    controls.PlaybackRate(std::clamp(Number(values, "rate"), .5, 2.));
    controls.ShuffleEnabled(Boolean(values, "shuffle"));
    const auto loop = Text(values, "loop");
    controls.AutoRepeatMode(loop == "Track" ? winrt::Windows::Media::MediaPlaybackAutoRepeatMode::Track
        : loop == "Playlist" ? winrt::Windows::Media::MediaPlaybackAutoRepeatMode::List
        : winrt::Windows::Media::MediaPlaybackAutoRepeatMode::None);
    controls.PlaybackStatus(Boolean(values, "playing") ? MediaPlaybackStatus::Playing : has_track ? MediaPlaybackStatus::Paused : MediaPlaybackStatus::Stopped);
    controls.IsNextEnabled(has_track); controls.IsPreviousEnabled(has_track); controls.IsPauseEnabled(has_track);
    const auto key = Text(values, "trackId") + Text(values, "title") + Text(values, "artist") + Text(values, "album");
    if (key != metadata_key) {
      auto updater = controls.DisplayUpdater();
      updater.Type(winrt::Windows::Media::MediaPlaybackType::Music);
      auto properties = updater.MusicProperties();
      properties.Title(winrt::to_hstring(Text(values, "title")));
      properties.Artist(winrt::to_hstring(Text(values, "artist")));
      properties.AlbumTitle(winrt::to_hstring(Text(values, "album")));
      updater.Update(); metadata_key = key;
    }
    winrt::Windows::Media::SystemMediaTransportControlsTimelineProperties timeline;
    timeline.StartTime(winrt::Windows::Foundation::TimeSpan{0});
    timeline.MinSeekTime(winrt::Windows::Foundation::TimeSpan{0});
    const int64_t duration = static_cast<int64_t>(Number(values, "duration")) * 10;
    const int64_t position = std::clamp(static_cast<int64_t>(Number(values, "position")) * 10, int64_t{0}, std::max(int64_t{0}, duration));
    timeline.EndTime(winrt::Windows::Foundation::TimeSpan{duration});
    timeline.MaxSeekTime(winrt::Windows::Foundation::TimeSpan{duration});
    timeline.Position(winrt::Windows::Foundation::TimeSpan{position});
    controls.UpdateTimelineProperties(timeline);
  }
};

DesktopIntegration::DesktopIntegration(flutter::BinaryMessenger* messenger, HWND window) : state_(std::make_unique<State>()) {
  state_->main_window = window;
  state_->channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(messenger, "top.nekoh2o/desktop", &flutter::StandardMethodCodec::GetInstance());
  state_->channel->SetMethodCallHandler([this](const auto& call, auto result) {
    try {
      if (call.method_name() == "initialize") {
        state_->StartTray();
        const bool media = state_->Initialize();
        result->Success(EncodableValue(EncodableMap{{EncodableValue("media"), EncodableValue(media)}, {EncodableValue("lyrics"), EncodableValue(true)}, {EncodableValue("positioning"), EncodableValue(true)}, {EncodableValue("tray"), EncodableValue(state_->tray_available)}}));
      } else if (call.method_name() == "configureTray") {
        const auto* values = call.arguments() == nullptr ? nullptr : std::get_if<EncodableMap>(call.arguments());
        state_->close_to_tray = values != nullptr && Boolean(*values, "closeToTray") && state_->tray_available;
        result->Success(EncodableValue(state_->close_to_tray));
      } else if (call.method_name() == "state") {
        const auto* values = call.arguments() == nullptr ? nullptr : std::get_if<EncodableMap>(call.arguments());
        if (values == nullptr) { result->Error("invalid_state", "Expected state map"); return; }
        state_->Update(*values); result->Success();
      } else if (call.method_name() == "dispose") { state_->Stop(); result->Success(); }
      else result->NotImplemented();
    } catch (...) { result->Error("desktop_unavailable", "System integration update failed"); }
  });
}

DesktopIntegration::~DesktopIntegration() {
  *state_->alive = false;
  state_->Stop();
  if (state_->lyrics_window != nullptr) DestroyWindow(state_->lyrics_window);
  state_->channel->SetMethodCallHandler(nullptr);
}

bool DesktopIntegration::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == state_->taskbar_created && state_->taskbar_created != 0) {
    // Explorer restarted: only re-add the icon while the tray is in use.
    if (!state_->tray_enabled) return true;
    state_->tray_available = false;
    state_->StartTray();
    state_->TrayChanged();
    return true;
  }
  if (message == WM_CLOSE && state_->close_to_tray && state_->tray_available && !state_->quitting) {
    ShowWindow(state_->main_window, SW_HIDE);
    return true;
  }
  if (message == kTrayAction) {
    const auto event = LOWORD(lparam);
    if (event == NIN_SELECT || event == NIN_KEYSELECT) state_->ShowMain();
    else if (event == WM_CONTEXTMENU) state_->TrayMenu();
    return true;
  }
  if (message == kMediaSetting) {
    if (!state_->controls) return true;
    switch (wparam) {
      case 1: state_->Setting("seek", EncodableValue(static_cast<int64_t>(lparam))); break;
      case 2: state_->Setting("rate", EncodableValue(static_cast<double>(lparam) / 10000)); break;
      case 3:
        switch (static_cast<winrt::Windows::Media::MediaPlaybackAutoRepeatMode>(lparam)) {
          case winrt::Windows::Media::MediaPlaybackAutoRepeatMode::None: state_->Setting("loop", EncodableValue("None")); break;
          case winrt::Windows::Media::MediaPlaybackAutoRepeatMode::Track: state_->Setting("loop", EncodableValue("Track")); break;
          case winrt::Windows::Media::MediaPlaybackAutoRepeatMode::List: state_->Setting("loop", EncodableValue("Playlist")); break;
          default: break;
        }
        break;
      case 4: state_->Setting("shuffle", EncodableValue(lparam != 0)); break;
      default: break;
    }
    return true;
  }
  if (message != kMediaAction) return false;
  if (!state_->controls) return true;
  switch (static_cast<SystemMediaTransportControlsButton>(wparam)) {
    case SystemMediaTransportControlsButton::Play: state_->Action("play"); break;
    case SystemMediaTransportControlsButton::Pause: state_->Action("pause"); break;
    case SystemMediaTransportControlsButton::Stop: state_->Action("stop"); break;
    case SystemMediaTransportControlsButton::Next: state_->Action("next"); break;
    case SystemMediaTransportControlsButton::Previous: state_->Action("previous"); break;
    default: break;
  }
  return true;
}
