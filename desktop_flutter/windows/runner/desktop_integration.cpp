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
#include <windowsx.h>

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
  std::wstring title_line;
  int font_size = 30;
  int64_t position = 0;
  int64_t duration = 0;
  bool playing = false;
  bool show_title = false;
  bool show_progress = false;
  bool show_controls = false;
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
  // Share / chat URL shown in the last balloon; forwarded to Dart on click.
  std::string notification_uri;
  std::string tray_tooltip_text = "NekoPlayer — 点击显示播放器";
  std::string tray_show_text = "显示播放器";
  std::string tray_toggle_text = "播放 / 暂停";
  std::string tray_previous_text = "上一首";
  std::string tray_next_text = "下一首";
  std::string tray_quit_text = "退出";
  std::string lyrics_window_title = "NekoPlayer 桌面歌词";

  void ApplyLabels(const EncodableMap& values) {
    const auto* found = Find(values, "labels");
    const auto* labels = found == nullptr ? nullptr : std::get_if<EncodableMap>(found);
    if (labels == nullptr) return;
    const auto read = [&](const char* key, std::string& target) {
      std::string value = Text(*labels, key);
      if (!value.empty()) target = value;
    };
    read("tooltip", tray_tooltip_text);
    read("show", tray_show_text);
    read("toggle", tray_toggle_text);
    read("previous", tray_previous_text);
    read("next", tray_next_text);
    read("quit", tray_quit_text);
    read("lyricsTitle", lyrics_window_title);
    if (tray_available) {
      wcsncpy_s(tray.szTip, Wide(tray_tooltip_text).c_str(), _TRUNCATE);
      Shell_NotifyIconW(NIM_MODIFY, &tray);
    }
    if (lyrics_window != nullptr) SetWindowTextW(lyrics_window, Wide(lyrics_window_title).c_str());
  }


  int OverlayHeight() const {
    int height = 20;
    if (show_title) height += 22;
    height += font_size * 3 / 2 + font_size;
    if (show_progress) height += 24;
    if (show_controls) height += 38;
    return std::max(100, height);
  }

  RECT ControlsRect(const RECT& area) const {
    const int width = 72 * 3 + 12 * 2;
    const int top = area.bottom - 38;
    return RECT{(area.right - width) / 2, top, (area.right + width) / 2, top + 28};
  }

  void ResizeLyrics() {
    if (lyrics_window == nullptr) return;
    RECT frame{};
    GetWindowRect(lyrics_window, &frame);
    const int height = OverlayHeight();
    if (height == frame.bottom - frame.top) return;
    const int width = frame.right - frame.left;
    SetWindowPos(lyrics_window, nullptr, frame.left, frame.bottom - height, width, height,
                 SWP_NOZORDER | SWP_NOACTIVATE);
  }

  void PaintControls(HDC buffer, const RECT& area) {
    const RECT row = ControlsRect(area);
    const int width = 72;
    const wchar_t* labels[3] = {L"◀◀", playing ? L"II" : L"▶", L"▶▶"};
    for (int index = 0; index < 3; index++) {
      RECT button{row.left + index * (width + 12), row.top,
                  row.left + index * (width + 12) + width, row.bottom};
      HBRUSH shade = CreateSolidBrush(index == 1 ? RGB(255, 140, 150) : RGB(46, 42, 54));
      FillRect(buffer, &button, shade);
      DeleteObject(shade);
      SetTextColor(buffer, index == 1 ? RGB(20, 19, 27) : RGB(232, 226, 240));
      DrawText(buffer, labels[index], -1, &button, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    }
  }

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
    wcsncpy_s(tray.szTip, Wide(tray_tooltip_text).c_str(), _TRUNCATE);
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
    AppendMenuW(menu, MF_STRING, 1, Wide(tray_show_text).c_str());
    AppendMenuW(menu, MF_STRING, 2, Wide(tray_toggle_text).c_str());
    AppendMenuW(menu, MF_STRING, 3, Wide(tray_previous_text).c_str());
    AppendMenuW(menu, MF_STRING, 4, Wide(tray_next_text).c_str());
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, 5, Wide(tray_quit_text).c_str());
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

  void Notify(const std::string& title, const std::string& body, const std::string& uri) {
    if (!tray_available) StartTray();
    if (!tray_available) return;
    notification_uri = uri;
    const std::wstring wide_title = Wide(title);
    const std::wstring wide_body = Wide(body);
    tray.uFlags |= NIF_INFO;
    tray.dwInfoFlags = NIIF_INFO;
    wcsncpy_s(tray.szInfoTitle, wide_title.empty() ? L"NekoPlayer" : wide_title.c_str(), _TRUNCATE);
    wcsncpy_s(tray.szInfo, wide_body.c_str(), _TRUNCATE);
    Shell_NotifyIconW(NIM_MODIFY, &tray);
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
          RECT area;
          GetClientRect(window, &area);
          const POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
          if (self->show_controls) {
            const RECT row = self->ControlsRect(area);
            if (PtInRect(&row, point)) {
              const int button_width = 72;
              const int index =
                  (point.x - row.left) / (button_width + 12);
              if (index >= 0 && index <= 2 && point.x < row.left + index * (button_width + 12) + button_width) {
                self->Action(index == 0 ? "previous" : index == 1 ? "toggle" : "next");
                return 0;
              }
            }
          }
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
        const auto font = [dpi](int points, int weight) {
          return CreateFont(-MulDiv(points, dpi, 96), 0, 0, 0, weight, FALSE, FALSE, FALSE,
                            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                            CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Microsoft YaHei");
        };
        HFONT title_font = font(std::max(11, self->font_size * 2 / 5), FW_NORMAL);
        HFONT primary = font(self->font_size, FW_BOLD);
        HFONT secondary = font(self->font_size * 2 / 3, FW_NORMAL);
        HFONT small_font = font(12, FW_NORMAL);
        const int padding = 12;
        int y = 10;
        const auto line = [&](const std::wstring& text, HFONT font_handle, COLORREF color, int height) {
          const auto previous = SelectObject(buffer, font_handle);
          SetTextColor(buffer, color);
          RECT rect{padding, y, area.right - padding, y + height};
          DrawText(buffer, text.c_str(), -1, &rect, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
          SelectObject(buffer, previous);
          y += height;
        };
        if (self->show_title) line(self->title_line, title_font, RGB(157, 148, 173), 22);
        line(self->lyric, primary, RGB(255, 140, 150), self->font_size * 3 / 2);
        line(self->next_lyric, secondary, RGB(202, 194, 220), self->font_size);
        if (self->show_progress) {
          const auto previous = SelectObject(buffer, small_font);
          wchar_t left[16];
          wchar_t right[16];
          wchar_t both[40];
          const auto clock = [](int64_t microseconds, wchar_t* out, size_t size) {
            const int64_t seconds = std::max<int64_t>(0, microseconds) / 1000000;
            swprintf_s(out, size, L"%lld:%02lld", static_cast<long long>(seconds / 60),
                       static_cast<long long>(seconds % 60));
          };
          clock(self->position, left, 16);
          clock(self->duration, right, 16);
          swprintf_s(both, L"%s / %s", left, right);
          const int text_width = 96;
          RECT time_rect{area.right - padding - text_width, y, area.right - padding, y + 20};
          SetTextColor(buffer, RGB(157, 148, 173));
          DrawText(buffer, both, -1, &time_rect, DT_RIGHT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
          RECT track{padding, y + 8, area.right - padding - text_width - 8, y + 14};
          HBRUSH back = CreateSolidBrush(RGB(60, 55, 70));
          FillRect(buffer, &track, back);
          DeleteObject(back);
          const double progress = self->duration > 0
              ? std::clamp(static_cast<double>(self->position) / static_cast<double>(self->duration), 0., 1.)
              : 0.;
          RECT filled{track.left, track.top,
                      track.left + static_cast<int>((track.right - track.left) * progress), track.bottom};
          HBRUSH accent = CreateSolidBrush(RGB(255, 140, 150));
          FillRect(buffer, &filled, accent);
          DeleteObject(accent);
          SelectObject(buffer, previous);
          y += 24;
        }
        if (self->show_controls) {
          const auto previous = SelectObject(buffer, small_font);
          self->PaintControls(buffer, area);
          SelectObject(buffer, previous);
        }
        BitBlt(target, 0, 0, area.right, area.bottom, buffer, 0, 0, SRCCOPY);
        DeleteObject(title_font); DeleteObject(primary); DeleteObject(secondary); DeleteObject(small_font);
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
    lyric = Wide(Text(values, "lyric"));
    next_lyric = Wide(Text(values, "nextLyric"));
    const std::wstring artist = Wide(Text(values, "artist"));
    title_line = Wide(Text(values, "title"));
    if (!artist.empty()) title_line += L" · " + artist;
    font_size = static_cast<int>(std::clamp(Number(values, "lyricsSize"), 18., 64.));
    position = static_cast<int64_t>(Number(values, "position"));
    duration = static_cast<int64_t>(Number(values, "duration"));
    playing = Boolean(values, "playing");
    show_title = Boolean(values, "showTitle");
    show_progress = Boolean(values, "showProgress");
    show_controls = Boolean(values, "showControls");
    locked = Boolean(values, "lyricsLocked");
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
      const int height = OverlayHeight();
      lyrics_window = CreateWindowEx(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED, kLyricsClass, Wide(lyrics_window_title).c_str(), WS_POPUP,
        info.rcWork.left + (info.rcWork.right - info.rcWork.left - width) / 2, info.rcWork.bottom - 50 - height, width, height, nullptr, nullptr, registration.hInstance, this);
    }
    if (lyrics_window == nullptr) return;
    LONG_PTR style = GetWindowLongPtr(lyrics_window, GWL_EXSTYLE);
    style = locked ? style | WS_EX_TRANSPARENT : style & ~WS_EX_TRANSPARENT;
    SetWindowLongPtr(lyrics_window, GWL_EXSTYLE, style);
    SetLayeredWindowAttributes(lyrics_window, 0, static_cast<BYTE>(std::clamp(Number(values, "lyricsOpacity"), .25, 1.) * 255), LWA_ALPHA);
    ResizeLyrics();
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
        if (values != nullptr) state_->ApplyLabels(*values);
        state_->close_to_tray = values != nullptr && Boolean(*values, "closeToTray") && state_->tray_available;
        result->Success(EncodableValue(state_->close_to_tray));
      } else if (call.method_name() == "state") {
        const auto* values = call.arguments() == nullptr ? nullptr : std::get_if<EncodableMap>(call.arguments());
        if (values == nullptr) { result->Error("invalid_state", "Expected state map"); return; }
        state_->Update(*values); result->Success();
      } else if (call.method_name() == "notify") {
        const auto* values = call.arguments() == nullptr ? nullptr : std::get_if<EncodableMap>(call.arguments());
        if (values != nullptr) state_->Notify(Text(*values, "title"), Text(*values, "body"), Text(*values, "uri"));
        result->Success();
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
    else if (event == NIN_BALLOONUSERCLICK) {
      state_->ShowMain();
      if (!state_->notification_uri.empty()) {
        state_->channel->InvokeMethod(
            "deepLink",
            std::make_unique<EncodableValue>(EncodableMap{{EncodableValue("uri"), EncodableValue(state_->notification_uri)}}));
        state_->notification_uri.clear();
      }
    }
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
