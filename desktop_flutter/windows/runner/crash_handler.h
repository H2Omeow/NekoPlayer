#ifndef RUNNER_CRASH_HANDLER_H_
#define RUNNER_CRASH_HANDLER_H_

// Native crash diagnostics. Logs live in
// %APPDATA%\top.nekoh2o\NekoPlayer\logs (crash dumps in logs\crash), or in
// NEKOPLAYER_LOG_DIR when set, matching the Dart side.
namespace crash_handler {

// Installs the unhandled-exception filter (minidump + text report), CRT
// abort / invalid-parameter / pure-call / terminate handlers. Call at the very
// start of wWinMain.
void Install();

// Sends stdout/stderr to logs\stderr.log. Call only when no console is
// attached; the caller should then resync the Flutter engine's streams.
// Returns true when the redirect took effect.
bool RedirectStandardStreams();

// Appends the exception currently being handled (call from inside a catch
// block) to logs\native.log. Never throws.
void LogCaughtException(const char* where);

// Appends |message| to logs\native.log. Never throws.
void LogNative(const char* message);

// Removes the unclean-shutdown marker (logs\session.json); call on orderly exit.
void MarkCleanExit();

}  // namespace crash_handler

#endif  // RUNNER_CRASH_HANDLER_H_
