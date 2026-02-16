#include "flutter_window.h"

#include <flutter_windows.h>

#include <cstdlib>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr int kMinWindowWidth = 640;
constexpr int kMinWindowHeight = 480;

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

void SaveWindowState(HWND hwnd) {
  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  if (!GetWindowPlacement(hwnd, &placement)) {
    return;
  }

  const RECT rect = placement.rcNormalPosition;
  const int physical_x = rect.left;
  const int physical_y = rect.top;
  const int physical_width = rect.right - rect.left;
  const int physical_height = rect.bottom - rect.top;

  const HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  const double scale = dpi / 96.0;

  const int x = static_cast<int>(std::lround(physical_x / scale));
  const int y = static_cast<int>(std::lround(physical_y / scale));
  const int width = static_cast<int>(std::lround(physical_width / scale));
  const int height = static_cast<int>(std::lround(physical_height / scale));
  if (width < kMinWindowWidth || height < kMinWindowHeight) {
    return;
  }

  const std::filesystem::path state_path = GetWindowStatePath();
  std::error_code ec;
  std::filesystem::create_directories(state_path.parent_path(), ec);

  std::wofstream file(state_path, std::ios::trunc);
  if (!file.is_open()) {
    return;
  }
  // v2 format: version x y width height (all in logical pixels).
  file << 2 << L' ' << x << L' ' << y << L' ' << width << L' ' << height
       << L'\n';
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_CLOSE:
      SaveWindowState(hwnd);
      break;

    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
