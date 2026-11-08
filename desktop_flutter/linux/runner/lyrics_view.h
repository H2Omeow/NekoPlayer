#pragma once

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Embeds the dynamic lyrics web page as a WebKitGTK overlay above the Flutter
// view. WebKitGTK is loaded with dlopen at first use so it stays optional.
struct LyricsView;
LyricsView* lyrics_view_new(FlView* view, GtkOverlay* overlay);
void lyrics_view_free(LyricsView* lyrics_view);
