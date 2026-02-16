#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>
#include <cstdlib>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {
constexpr int kDefaultWindowWidth = 1280;
constexpr int kDefaultWindowHeight = 720;
constexpr int kDefaultWindowX = 10;
constexpr int kDefaultWindowY = 10;
constexpr int kMinWindowWidth = 640;
constexpr int kMinWindowHeight = 480;
constexpr int kMaxWindowWidth = 7680;
constexpr int kMaxWindowHeight = 4320;

struct InitialWindowState {
  Win32Window::Point origin;
  Win32Window::Size size;
};

std::filesystem::path GetWindowStatePath() {
  wchar_t* app_data_buffer = nullptr;
  size_t app_data_len = 0;
  const errno_t env_result =
      _wdupenv_s(&app_data_buffer, &app_data_len, L"APPDATA");
  if (env_result != 0 || app_data_buffer == nullptr || app_data_len == 0) {
    if (app_data_buffer != nullptr) {
      free(app_data_buffer);
    }
    return std::filesystem::path(L"window_state.txt");
  }

  const std::filesystem::path app_data_path(app_data_buffer);
  free(app_data_buffer);

  return app_data_path / L"bookmark_app" /
         L"window_state.txt";
}

bool IsWindowVisibleOnAnyMonitor(const RECT& rect) {
  const int min_x = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int min_y = GetSystemMetrics(SM_YVIRTUALSCREEN);
  const int max_x = min_x + GetSystemMetrics(SM_CXVIRTUALSCREEN);
  const int max_y = min_y + GetSystemMetrics(SM_CYVIRTUALSCREEN);

  return rect.right > min_x && rect.left < max_x && rect.bottom > min_y &&
         rect.top < max_y;
}

double GetScaleForPoint(int x, int y) {
  const POINT target_point = {x, y};
  const HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  return dpi / 96.0;
}

int ToLogical(int physical, double scale) {
  return static_cast<int>(std::lround(physical / scale));
}

InitialWindowState LoadInitialWindowState() {
  InitialWindowState fallback{
      Win32Window::Point(kDefaultWindowX, kDefaultWindowY),
      Win32Window::Size(kDefaultWindowWidth, kDefaultWindowHeight),
  };

  const std::filesystem::path state_path = GetWindowStatePath();
  if (!std::filesystem::exists(state_path)) {
    return fallback;
  }

  std::wifstream file(state_path);
  if (!file.is_open()) {
    return fallback;
  }

  std::vector<int> values;
  int value = 0;
  while (file >> value) {
    values.push_back(value);
  }

  if (values.size() < 2) {
    return fallback;
  }

  int x = kDefaultWindowX;
  int y = kDefaultWindowY;
  int width = values[0];
  int height = values[1];

  if (values.size() >= 5 && values[0] == 2) {
    x = values[1];
    y = values[2];
    width = values[3];
    height = values[4];
  } else if (values.size() >= 4) {
    // Legacy format without version used physical pixels.
    const int physical_x = values[0];
    const int physical_y = values[1];
    const int physical_width = values[2];
    const int physical_height = values[3];
    const double scale = GetScaleForPoint(physical_x, physical_y);
    x = ToLogical(physical_x, scale);
    y = ToLogical(physical_y, scale);
    width = ToLogical(physical_width, scale);
    height = ToLogical(physical_height, scale);
  } else {
    // Legacy size-only format used physical pixels.
    const double scale = GetScaleForPoint(kDefaultWindowX, kDefaultWindowY);
    width = ToLogical(values[0], scale);
    height = ToLogical(values[1], scale);
  }

  if (width < kMinWindowWidth || height < kMinWindowHeight ||
      width > kMaxWindowWidth || height > kMaxWindowHeight) {
    return fallback;
  }

  const RECT rect = {x, y, x + width, y + height};
  if (!IsWindowVisibleOnAnyMonitor(rect)) {
    return fallback;
  }

  return InitialWindowState{
      Win32Window::Point(x, y),
      Win32Window::Size(static_cast<unsigned int>(width),
                        static_cast<unsigned int>(height)),
  };
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

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  const InitialWindowState initial_state = LoadInitialWindowState();
  const Win32Window::Point origin = initial_state.origin;
  const Win32Window::Size size = initial_state.size;
  if (!window.Create(L"\u7CAE\u4ED3", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
