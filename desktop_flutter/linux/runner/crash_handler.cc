#include "crash_handler.h"

#include <execinfo.h>
#include <fcntl.h>
#include <glib.h>
#include <glib/gstdio.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#include <exception>
#include <stdexcept>
#include <typeinfo>
#include <cxxabi.h>

namespace {

constexpr size_t kPathMax = 1024;
constexpr size_t kAltStackSize = 128 * 1024;
constexpr int kFrames = 64;

// Everything the signal handler needs is prepared up front so it only calls
// async-signal-safe functions (open/write/close/time/backtrace after warm-up).
char g_logs_dir[kPathMax];
char g_crash_path[kPathMax];
char g_native_log_path[kPathMax];
char g_marker_path[kPathMax];
char g_executable[kPathMax];
alignas(16) char g_alt_stack[kAltStackSize];
char g_maps_buffer[4096];
bool g_installed = false;
volatile sig_atomic_t g_in_handler = 0;
GMutex g_log_mutex;
int g_native_lines = 0;

void write_all(int fd, const char* data, size_t length) {
  while (length > 0) {
    const ssize_t written = write(fd, data, length);
    if (written <= 0) return;
    data += written;
    length -= static_cast<size_t>(written);
  }
}

void write_text(int fd, const char* text) { write_all(fd, text, strlen(text)); }

void write_number(int fd, long long value, int base = 10) {
  char buffer[32];
  size_t index = sizeof(buffer);
  const bool negative = value < 0 && base == 10;
  unsigned long long magnitude = negative ? 0ULL - static_cast<unsigned long long>(value)
                                          : static_cast<unsigned long long>(value);
  do {
    buffer[--index] = "0123456789abcdef"[magnitude % static_cast<unsigned>(base)];
    magnitude /= static_cast<unsigned>(base);
  } while (magnitude != 0 && index > 0);
  if (negative && index > 0) buffer[--index] = '-';
  write_all(fd, buffer + index, sizeof(buffer) - index);
}

void write_hex(int fd, unsigned long long value) {
  write_text(fd, "0x");
  write_number(fd, static_cast<long long>(value), 16);
}

const char* signal_name(int signal_number) {
  switch (signal_number) {
    case SIGSEGV: return "SIGSEGV";
    case SIGBUS: return "SIGBUS";
    case SIGILL: return "SIGILL";
    case SIGFPE: return "SIGFPE";
    case SIGABRT: return "SIGABRT";
    default: return "signal";
  }
}

void write_backtrace(int fd) {
  void* frames[kFrames];
  const int count = backtrace(frames, kFrames);
  backtrace_symbols_fd(frames, count, fd);
}

void write_maps(int fd) {
  const int maps = open("/proc/self/maps", O_RDONLY | O_CLOEXEC);
  if (maps < 0) return;
  for (;;) {
    const ssize_t count = read(maps, g_maps_buffer, sizeof(g_maps_buffer));
    if (count <= 0) break;
    write_all(fd, g_maps_buffer, static_cast<size_t>(count));
  }
  close(maps);
}

void write_preamble(int fd, const char* title) {
  write_text(fd, "NekoPlayer native crash report\n");
  write_text(fd, title);
  write_text(fd, "\npid: ");
  write_number(fd, getpid());
  write_text(fd, " tid: ");
  write_number(fd, syscall(SYS_gettid));
  write_text(fd, "\ntime(unix): ");
  write_number(fd, static_cast<long long>(time(nullptr)));
  write_text(fd, "\nexe: ");
  write_text(fd, g_executable);
  write_text(fd, "\n");
}

int open_crash_file() {
  if (g_crash_path[0] == '\0') return STDERR_FILENO;
  const int fd = open(g_crash_path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
  return fd < 0 ? STDERR_FILENO : fd;
}

void fatal_signal(int signal_number, siginfo_t* info, void*) {
  // SA_RESETHAND restored the default action; a second fault while writing
  // the report simply kills the process.
  if (g_in_handler) _exit(128 + signal_number);
  g_in_handler = 1;
  const int fd = open_crash_file();
  write_preamble(fd, "fatal signal");
  write_text(fd, "signal: ");
  write_number(fd, signal_number);
  write_text(fd, " (");
  write_text(fd, signal_name(signal_number));
  write_text(fd, ")");
  if (info != nullptr) {
    write_text(fd, " code=");
    write_number(fd, info->si_code);
    write_text(fd, " addr=");
    write_hex(fd, reinterpret_cast<unsigned long long>(info->si_addr));
  }
  write_text(fd, "\n--- backtrace ---\n");
  write_backtrace(fd);
  write_text(fd, "--- /proc/self/maps ---\n");
  write_maps(fd);
  write_text(fd, "--- end ---\n");
  if (fd != STDERR_FILENO) close(fd);
  // Re-raise with the default action so the shell/core dump see the signal.
  raise(signal_number);
}

void native_log(const char* text) {
  if (g_native_log_path[0] == '\0') return;
  g_mutex_lock(&g_log_mutex);
  if (g_native_lines < 500) {
    g_native_lines++;
    FILE* file = fopen(g_native_log_path, "a");
    if (file != nullptr) {
      const time_t now = time(nullptr);
      struct tm local {};
      localtime_r(&now, &local);
      char stamp[32];
      strftime(stamp, sizeof(stamp), "%Y-%m-%dT%H:%M:%S", &local);
      fprintf(file, "%s %s\n", stamp, text);
      fclose(file);
    }
  }
  g_mutex_unlock(&g_log_mutex);
}

void terminate_handler() {
  const int fd = open_crash_file();
  write_preamble(fd, "uncaught C++ exception (std::terminate)");
  const std::type_info* type = abi::__cxa_current_exception_type();
  if (type != nullptr) {
    write_text(fd, "type: ");
    int status = 0;
    char* name = abi::__cxa_demangle(type->name(), nullptr, nullptr, &status);
    write_text(fd, status == 0 && name != nullptr ? name : type->name());
    free(name);
    write_text(fd, "\n");
    try {
      throw;
    } catch (const std::exception& error) {
      write_text(fd, "what: ");
      write_text(fd, error.what());
      write_text(fd, "\n");
    } catch (...) {
    }
  } else {
    write_text(fd, "terminate called without an active exception\n");
  }
  write_text(fd, "--- backtrace ---\n");
  write_backtrace(fd);
  if (fd != STDERR_FILENO) close(fd);
  abort();  // SIGABRT handler appends its own backtrace and maps
}

void exit_logger(int status, void*) {
  if (status == 0) {
    // Orderly shutdown: drop the unclean-exit marker written at launch.
    if (g_marker_path[0] != '\0') unlink(g_marker_path);
    return;
  }
  char line[64];
  snprintf(line, sizeof(line), "exit() called with status %d; backtrace:", status);
  native_log(line);
  if (g_native_log_path[0] != '\0') {
    const int fd = open(g_native_log_path, O_WRONLY | O_APPEND | O_CLOEXEC);
    if (fd >= 0) {
      write_backtrace(fd);
      close(fd);
    }
  }
}

GLogWriterOutput glib_writer(GLogLevelFlags level, const GLogField* fields,
                             gsize n_fields, gpointer) {
  if (level & (G_LOG_LEVEL_ERROR | G_LOG_LEVEL_CRITICAL | G_LOG_LEVEL_WARNING)) {
    const char* domain = "";
    const char* message = "";
    for (gsize index = 0; index < n_fields; index++) {
      if (g_strcmp0(fields[index].key, "GLIB_DOMAIN") == 0) {
        domain = static_cast<const char*>(fields[index].value);
      } else if (g_strcmp0(fields[index].key, "MESSAGE") == 0) {
        message = static_cast<const char*>(fields[index].value);
      }
    }
    const char* label = (level & G_LOG_LEVEL_ERROR)      ? "ERROR"
                        : (level & G_LOG_LEVEL_CRITICAL) ? "CRITICAL"
                                                         : "WARNING";
    g_autofree gchar* line = g_strdup_printf("[glib %s] %s: %s", label, domain, message);
    native_log(line);
  }
  return g_log_writer_default(level, fields, n_fields, nullptr);
}

void ensure_directory(const char* path) { g_mkdir_with_parents(path, 0755); }

void rotate_native_log() {
  struct stat info {};
  if (stat(g_native_log_path, &info) == 0 && info.st_size > 1024 * 1024) {
    g_autofree gchar* old = g_strconcat(g_native_log_path, ".1", nullptr);
    rename(g_native_log_path, old);
  }
}

void install_signals() {
  stack_t stack{};
  stack.ss_sp = g_alt_stack;
  stack.ss_size = sizeof(g_alt_stack);
  sigaltstack(&stack, nullptr);
  struct sigaction action {};
  action.sa_sigaction = fatal_signal;
  sigemptyset(&action.sa_mask);
  action.sa_flags = SA_SIGINFO | SA_ONSTACK | SA_RESETHAND;
  for (const int signal_number : {SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT}) {
    sigaction(signal_number, &action, nullptr);
  }
}

#ifndef NDEBUG
// Debug-only fault injection to verify the handlers, e.g.
// NEKOPLAYER_TEST_CRASH=segv|abort|terminate|exit.
void maybe_trigger_test_crash() {
  const char* mode = getenv("NEKOPLAYER_TEST_CRASH");
  if (mode == nullptr) return;
  if (strcmp(mode, "segv") == 0) {
    *static_cast<volatile int*>(nullptr) = 1;
  } else if (strcmp(mode, "abort") == 0) {
    abort();
  } else if (strcmp(mode, "terminate") == 0) {
    throw std::runtime_error("NEKOPLAYER_TEST_CRASH=terminate");
  } else if (strcmp(mode, "exit") == 0) {
    exit(3);
  }
}
#endif

}  // namespace

void crash_handler_install(const char* application_id) {
  if (g_installed) return;
  g_installed = true;

  ssize_t length = readlink("/proc/self/exe", g_executable, sizeof(g_executable) - 1);
  g_executable[length > 0 ? length : 0] = '\0';

  // Same override as the Dart side (defaultLogRoot) so both write one place.
  const char* override_dir = getenv("NEKOPLAYER_LOG_DIR");
  g_autofree gchar* logs =
      override_dir != nullptr && override_dir[0] != '\0'
          ? g_strdup(override_dir)
          : g_build_filename(g_get_user_data_dir(), application_id, "logs",
                             nullptr);
  g_autofree gchar* crash_directory = g_build_filename(logs, "crash", nullptr);
  ensure_directory(crash_directory);
  g_snprintf(g_logs_dir, sizeof(g_logs_dir), "%s", logs);
  g_snprintf(g_crash_path, sizeof(g_crash_path), "%s/crash-%lld-%d.txt", crash_directory,
             static_cast<long long>(time(nullptr)), static_cast<int>(getpid()));
  g_snprintf(g_native_log_path, sizeof(g_native_log_path), "%s/native.log", logs);
  g_snprintf(g_marker_path, sizeof(g_marker_path), "%s/session.json", logs);
  rotate_native_log();

  // Warm up backtrace() so its first call (which may load libgcc) does not
  // happen inside a signal handler.
  void* warm[4];
  backtrace(warm, 4);

  install_signals();
  std::set_terminate(terminate_handler);
  on_exit(exit_logger, nullptr);
  g_log_set_writer_func(glib_writer, nullptr, nullptr);
#ifndef NDEBUG
  maybe_trigger_test_crash();
#endif
}
