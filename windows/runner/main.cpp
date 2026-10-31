#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

#include <algorithm>

namespace {

// Fenêtre « 2e écran » (SecurGYM.exe --access-display) : on la place sur le
// moniteur secondaire s'il existe.
BOOL CALLBACK FindSecondaryMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
  MONITORINFO info{};
  info.cbSize = sizeof(MONITORINFO);
  if (::GetMonitorInfo(monitor, &info) && !(info.dwFlags & MONITORINFOF_PRIMARY)) {
    *reinterpret_cast<RECT*>(data) = info.rcWork;
    return FALSE;
  }
  return TRUE;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  const bool access_display =
      std::any_of(command_line_arguments.begin(), command_line_arguments.end(),
                  [](const std::string& arg) {
                    return arg == "--access-display" || arg == "--tablet-access";
                  });

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(access_display ? L"SecurGYM - Ecran d'acces" : L"SecurGYM",
                     origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);
  if (access_display) {
    RECT target{0, 0, 0, 0};
    ::EnumDisplayMonitors(nullptr, nullptr, FindSecondaryMonitor,
                          reinterpret_cast<LPARAM>(&target));
    HWND hwnd = window.GetHandle();
    if (target.right > target.left) {
      ::SetWindowPos(hwnd, nullptr, target.left, target.top,
                     target.right - target.left, target.bottom - target.top,
                     SWP_NOZORDER | SWP_NOACTIVATE);
    }
    window.SetStartMaximized(true);
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
