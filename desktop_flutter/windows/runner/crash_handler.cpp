#include "crash_handler.h"

#include <windows.h>

#include <dbghelp.h>
#include <intrin.h>
#include <fcntl.h>
#include <io.h>
#include <shellapi.h>
#include <shlobj.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <cwchar>
#include <exception>
#include <string>
#include <typeinfo>

namespace {

using MiniDumpWriteDumpFn = BOOL(WINAPI*)(HANDLE, DWORD, HANDLE, MINIDUMP_TYPE,
                                          PMINIDUMP_EXCEPTION_INFORMATION,
                                          PMINIDUMP_USER_STREAM_INFORMATION,
                                          PMINIDUMP_CALLBACK_INFORMATION);

constexpr DWORD kSyntheticExceptionCode = 0xE0000001;

std::wstring g_logs_dir;
std::wstring g_crash_dir;
std::atomic<bool> g_reporting{false};
bool g_installed = false;

struct ReportRequest {
  const wchar_t* title;
  EXCEPTION_POINTERS* pointers;
  DWORD thread_id;
  std::string detail;
};

std::wstring KnownRoamingAppData() {
  PWSTR raw = nullptr;
  std::wstring result;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, KF_FLAG_DEFAULT, nullptr, &raw)) &&
      raw != nullptr) {
    result = raw;
  }
  if (raw != nullptr) CoTaskMemFree(raw);
  return result;
}

std::wstring Stamp() {
  SYSTEMTIME time;
  GetLocalTime(&time);
  wchar_t text[64];
  swprintf_s(text, L"%04d%02d%02d-%02d%02d%02d", time.wYear, time.wMonth, time.wDay,
             time.wHour, time.wMinute, time.wSecond);
  return text;
}

std::wstring ModuleFor(const void* address, ULONG_PTR* offset) {
  HMODULE module = nullptr;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          static_cast<LPCWSTR>(address), &module) ||
      module == nullptr) {
    *offset = reinterpret_cast<ULONG_PTR>(address);
    return L"?";
  }
  wchar_t name[MAX_PATH] = L"?";
  GetModuleFileNameW(module, name, MAX_PATH);
  *offset = reinterpret_cast<ULONG_PTR>(address) - reinterpret_cast<ULONG_PTR>(module);
  const wchar_t* base = wcsrchr(name, L'\\');
  return base != nullptr ? base + 1 : name;
}

void AppendLine(HANDLE file, const std::wstring& text) {
  // UTF-8 conversion keeps the report readable regardless of console codepage.
  const int size = WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                                       nullptr, 0, nullptr, nullptr);
  if (size <= 0) return;
  std::string bytes(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), bytes.data(),
                      size, nullptr, nullptr);
  DWORD written = 0;
  WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr);
}

std::wstring Hex(ULONG_PTR value) {
  wchar_t text[32];
  swprintf_s(text, L"0x%llx", static_cast<unsigned long long>(value));
  return text;
}

void WriteSidecar(const std::wstring& path, const ReportRequest& request) {
  const HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                                  OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  AppendLine(file, L"NekoPlayer native crash report\r\n");
  AppendLine(file, std::wstring(request.title) + L"\r\n");
  wchar_t line[256];
  swprintf_s(line, L"pid: %lu  crashing thread: %lu\r\n", GetCurrentProcessId(),
             request.thread_id);
  AppendLine(file, line);
  if (!request.detail.empty()) {
    const std::wstring detail(request.detail.begin(), request.detail.end());
    AppendLine(file, L"detail: " + detail + L"\r\n");
  }
  if (request.pointers != nullptr && request.pointers->ExceptionRecord != nullptr) {
    const EXCEPTION_RECORD* record = request.pointers->ExceptionRecord;
    AppendLine(file, L"exception code: " + Hex(record->ExceptionCode) + L"\r\n");
    ULONG_PTR offset = 0;
    const std::wstring module = ModuleFor(record->ExceptionAddress, &offset);
    AppendLine(file, L"exception address: " + Hex(reinterpret_cast<ULONG_PTR>(record->ExceptionAddress)) +
                         L" (" + module + L"+" + Hex(offset) + L")\r\n");
    if ((record->ExceptionCode == EXCEPTION_ACCESS_VIOLATION ||
         record->ExceptionCode == EXCEPTION_IN_PAGE_ERROR) &&
        record->NumberParameters >= 2) {
      const wchar_t* kind = record->ExceptionInformation[0] == 0   ? L"read"
                            : record->ExceptionInformation[0] == 1 ? L"write"
                                                                   : L"execute";
      AppendLine(file, std::wstring(L"access violation: ") + kind + L" of " +
                           Hex(record->ExceptionInformation[1]) + L"\r\n");
    }
  }
  void* frames[48];
  const USHORT count = CaptureStackBackTrace(0, 48, frames, nullptr);
  AppendLine(file, L"--- stack (module+offset) ---\r\n");
  for (USHORT index = 0; index < count; index++) {
    ULONG_PTR offset = 0;
    const std::wstring module = ModuleFor(frames[index], &offset);
    AppendLine(file, module + L"+" + Hex(offset) + L"\r\n");
  }
  CloseHandle(file);
}

void WriteDump(const std::wstring& path, const ReportRequest& request) {
  // dbghelp comes from System32 only, never from the application directory.
  const HMODULE library = LoadLibraryExW(L"dbghelp.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (library == nullptr) return;
  const auto write = reinterpret_cast<MiniDumpWriteDumpFn>(GetProcAddress(library, "MiniDumpWriteDump"));
  if (write != nullptr) {
    const HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                                    FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file != INVALID_HANDLE_VALUE) {
      MINIDUMP_EXCEPTION_INFORMATION information{};
      information.ThreadId = request.thread_id;
      information.ExceptionPointers = request.pointers;
      information.ClientPointers = FALSE;
      const auto type = static_cast<MINIDUMP_TYPE>(MiniDumpWithIndirectlyReferencedMemory |
                                                   MiniDumpWithThreadInfo |
                                                   MiniDumpWithUnloadedModules);
      write(GetCurrentProcess(), GetCurrentProcessId(), file, type,
            request.pointers != nullptr ? &information : nullptr, nullptr, nullptr);
      CloseHandle(file);
    }
  }
  FreeLibrary(library);
}

DWORD WINAPI ReportThread(LPVOID data) {
  const auto* request = static_cast<const ReportRequest*>(data);
  const std::wstring base = g_crash_dir + L"\\crash-" + Stamp() + L"-" +
                            std::to_wstring(GetCurrentProcessId());
  WriteSidecar(base + L".txt", *request);
  WriteDump(base + L".dmp", *request);
  return 0;
}

// Runs on a fresh thread so a stack overflow in the faulting thread cannot
// prevent the report from being written.
void WriteReport(const wchar_t* title, EXCEPTION_POINTERS* pointers, const std::string& detail) {
  if (g_crash_dir.empty()) return;
  bool expected = false;
  if (!g_reporting.compare_exchange_strong(expected, true)) return;
  ReportRequest request{title, pointers, GetCurrentThreadId(), detail};
  const HANDLE thread = CreateThread(nullptr, 256 * 1024, ReportThread, &request, 0, nullptr);
  if (thread != nullptr) {
    WaitForSingleObject(thread, 30000);
    CloseHandle(thread);
  }
}

// Report for non-SEH failures (abort, invalid parameter, terminate): build a
// synthetic exception so the dump has a context for the calling thread.
__declspec(noinline) void ReportSynthetic(const wchar_t* title, const std::string& detail) {
  CONTEXT context{};
  RtlCaptureContext(&context);
  EXCEPTION_RECORD record{};
  record.ExceptionCode = kSyntheticExceptionCode;
  record.ExceptionAddress = _ReturnAddress();
  EXCEPTION_POINTERS pointers{&record, &context};
  WriteReport(title, &pointers, detail);
}

LONG WINAPI UnhandledFilter(EXCEPTION_POINTERS* pointers) {
  WriteReport(L"unhandled exception", pointers, std::string());
  return EXCEPTION_EXECUTE_HANDLER;
}

// Flutter 3.47.7 dereferences a null AXNode parent in
// AccessibilityBridge::CreateRemoveReparentedNodesUpdate when an accessibility
// client attaches (flutter/flutter#175041). The WM_GETOBJECT filter in
// flutter_window.cpp normally prevents the bridge from being created, but a
// request that arrives before the filter is installed still enables it. This
// handler catches that exact fault and resumes at the loop's "skip this
// child" path, matching the upstream fix (flutter/flutter#190903).
// The instruction offsets are specific to the x64 engine binary.
#if defined(_M_X64)
constexpr ULONG_PTR kEngineFaultOffset = 0x3c1ca;
constexpr ULONG_PTR kEngineCodeOffset = 0x3c1c6;
constexpr ULONG_PTR kEngineContinueOffset = 0x3c2ac;

constexpr BYTE kEngineCode[] = {
    0x48, 0x8b, 0x40, 0x20, 0x8b, 0x40, 0x48, 0x3b,
    0x46, 0x18, 0x0f, 0x84, 0xd6, 0x00, 0x00, 0x00,
};
constexpr BYTE kEngineContinue[] = {
    0x49, 0x83, 0xc5, 0x04, 0x4d, 0x39, 0xe5,
    0x0f, 0x85, 0xed, 0xfe, 0xff, 0xff,
};

LONG CALLBACK EngineAccessibilityHotfix(EXCEPTION_POINTERS* pointers) {
  thread_local bool handling = false;
  if (handling || pointers == nullptr || pointers->ExceptionRecord == nullptr ||
      pointers->ContextRecord == nullptr) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  EXCEPTION_RECORD* record = pointers->ExceptionRecord;
  if (record->ExceptionCode != EXCEPTION_ACCESS_VIOLATION ||
      record->NumberParameters < 2 || record->ExceptionInformation[0] != 0 ||
      record->ExceptionInformation[1] != 0x48) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  HMODULE engine = GetModuleHandleW(L"flutter_windows.dll");
  if (engine == nullptr) return EXCEPTION_CONTINUE_SEARCH;
  const ULONG_PTR base = reinterpret_cast<ULONG_PTR>(engine);
  CONTEXT* context = pointers->ContextRecord;
  if (context->Rip != base + kEngineFaultOffset ||
      std::memcmp(reinterpret_cast<const void*>(base + kEngineCodeOffset),
                  kEngineCode, sizeof(kEngineCode)) != 0 ||
      std::memcmp(reinterpret_cast<const void*>(base + kEngineContinueOffset),
                  kEngineContinue, sizeof(kEngineContinue)) != 0) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  handling = true;
  crash_handler::LogNative(
      "hotfix: skipped Flutter accessibility node with null parent "
      "(flutter/flutter#175041)");
  context->Rip = static_cast<DWORD64>(base + kEngineContinueOffset);
  handling = false;
  return EXCEPTION_CONTINUE_EXECUTION;
}
#endif  // defined(_M_X64)

void AbortSignal(int) {
  ReportSynthetic(L"abort() called (SIGABRT)", std::string());
  TerminateProcess(GetCurrentProcess(), 3);
}

void InvalidParameter(const wchar_t*, const wchar_t*, const wchar_t*, unsigned int, uintptr_t) {
  ReportSynthetic(L"CRT invalid parameter", std::string());
  TerminateProcess(GetCurrentProcess(), 3);
}

void PureCall() {
  ReportSynthetic(L"pure virtual function call", std::string());
  TerminateProcess(GetCurrentProcess(), 3);
}

void TerminateHandler() {
  std::string detail;
  try {
    throw;
  } catch (const std::exception& error) {
    detail = std::string(typeid(error).name()) + ": " + error.what();
  } catch (...) {
    detail = "non-standard exception or no active exception";
  }
  ReportSynthetic(L"std::terminate", detail);
  TerminateProcess(GetCurrentProcess(), 3);
}

void EnsureDirectories() {
  // Same override as the Dart side (defaultLogRoot) so both write one place.
  wchar_t override_dir[MAX_PATH];
  const DWORD length =
      GetEnvironmentVariableW(L"NEKOPLAYER_LOG_DIR", override_dir, MAX_PATH);
  if (length > 0 && length < MAX_PATH) {
    g_logs_dir = override_dir;
  } else {
    const std::wstring base = KnownRoamingAppData();
    if (base.empty()) return;
    g_logs_dir = base + L"\\top.nekoh2o\\NekoPlayer\\logs";
  }
  g_crash_dir = g_logs_dir + L"\\crash";
  if (SHCreateDirectoryExW(nullptr, g_crash_dir.c_str(), nullptr) != ERROR_SUCCESS &&
      GetFileAttributesW(g_crash_dir.c_str()) == INVALID_FILE_ATTRIBUTES) {
    g_crash_dir.clear();
  }
}

#ifdef _DEBUG
// Debug-only fault injection: NEKOPLAYER_TEST_CRASH=segv|abort|terminate.
void MaybeTriggerTestCrash() {
  wchar_t mode[32] = L"";
  if (GetEnvironmentVariableW(L"NEKOPLAYER_TEST_CRASH", mode, 32) == 0) return;
  if (wcscmp(mode, L"segv") == 0) {
    *static_cast<volatile int*>(nullptr) = 1;
  } else if (wcscmp(mode, L"abort") == 0) {
    abort();
  } else if (wcscmp(mode, L"terminate") == 0) {
    throw 1;
  }
}
#endif

}  // namespace

namespace crash_handler {

void Install() {
  if (g_installed) return;
  g_installed = true;
  EnsureDirectories();
#if defined(_M_X64)
  AddVectoredExceptionHandler(1, EngineAccessibilityHotfix);
#endif
  SetUnhandledExceptionFilter(UnhandledFilter);
  signal(SIGABRT, AbortSignal);
  _set_abort_behavior(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);
  _set_invalid_parameter_handler(InvalidParameter);
  _set_purecall_handler(PureCall);
  std::set_terminate(TerminateHandler);
#ifdef _DEBUG
  MaybeTriggerTestCrash();
#endif
}

bool RedirectStandardStreams() {
  if (g_logs_dir.empty()) return false;
  const std::wstring path = g_logs_dir + L"\\stderr.log";
  WIN32_FILE_ATTRIBUTE_DATA info{};
  if (GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &info) &&
      info.nFileSizeHigh == 0 && info.nFileSizeLow > 1024 * 1024) {
    MoveFileExW(path.c_str(), (path + L".1").c_str(), MOVEFILE_REPLACE_EXISTING);
  }
  const HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                  nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  SetStdHandle(STD_OUTPUT_HANDLE, file);
  SetStdHandle(STD_ERROR_HANDLE, file);
  FILE* unused = nullptr;
  freopen_s(&unused, "NUL", "w", stdout);
  freopen_s(&unused, "NUL", "w", stderr);
  const int descriptor = _open_osfhandle(reinterpret_cast<intptr_t>(file), _O_APPEND);
  if (descriptor >= 0) {
    _dup2(descriptor, 1);
    _dup2(descriptor, 2);
  }
  setvbuf(stderr, nullptr, _IONBF, 0);
  return true;
}

void LogNative(const char* message) {
  if (g_logs_dir.empty()) return;
  const std::string line = std::string("[") + std::to_string(GetTickCount64()) +
                           "] " + (message != nullptr ? message : "") + "\r\n";
  const HANDLE file = CreateFileW((g_logs_dir + L"\\native.log").c_str(), FILE_APPEND_DATA,
                                  FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS,
                                  FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  DWORD written = 0;
  WriteFile(file, line.data(), static_cast<DWORD>(line.size()), &written, nullptr);
  CloseHandle(file);
}

void LogCaughtException(const char* where) {
  if (g_logs_dir.empty()) return;
  std::string detail;
  try {
    throw;
  } catch (const std::exception& error) {
    detail = std::string(typeid(error).name()) + ": " + error.what();
  } catch (...) {
    detail = "non-standard exception";
  }
  const std::string line = std::string("[") + std::to_string(GetTickCount64()) + "] caught in " +
                           (where != nullptr ? where : "?") + ": " + detail + "\r\n";
  const HANDLE file = CreateFileW((g_logs_dir + L"\\native.log").c_str(), FILE_APPEND_DATA,
                                  FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS,
                                  FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  DWORD written = 0;
  WriteFile(file, line.data(), static_cast<DWORD>(line.size()), &written, nullptr);
  CloseHandle(file);
}

void MarkCleanExit() {
  if (g_logs_dir.empty()) return;
  DeleteFileW((g_logs_dir + L"\\session.json").c_str());
}

}  // namespace crash_handler
