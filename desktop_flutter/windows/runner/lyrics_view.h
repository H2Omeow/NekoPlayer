#pragma once

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <memory>

// Embeds the dynamic lyrics web page as a WebView2 child of the top-level
// window, above the Flutter view. Without the WebView2 runtime (or SDK at
// build time) the channel reports it as unavailable and Dart falls back to
// the external browser.
class LyricsView {
 public:
  LyricsView(flutter::BinaryMessenger* messenger, HWND window, HWND flutter_view);
  ~LyricsView();
  void HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  struct State;
  std::shared_ptr<State> state_;
};
