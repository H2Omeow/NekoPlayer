#pragma once

// Installs native crash diagnostics: fatal-signal backtraces, terminate and
// exit logging, GLib warning capture. Call first thing in main().
// Files go to <user data dir>/<application id>/logs (crash/ for crashes).
void crash_handler_install(const char* application_id);
