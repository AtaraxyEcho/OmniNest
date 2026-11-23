// Single-instance runner for OmniNest on Windows.
// Winsock2 must be included before windows.h to avoid winsock.h conflicts.
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

#pragma comment(lib, "Ws2_32.lib")

namespace {

constexpr wchar_t kSingleInstanceMutexName[] = L"Local\\OmniNestSingleInstance";
// Must match kOmniNestSingleInstancePort in
// lib/platform/desktop/desktop_single_instance.dart. Change both together.
constexpr int kActivatePort = 47683;

bool ContainsDeepLink(const std::vector<std::string>& args, std::string* out_uri) {
  for (const auto& arg : args) {
    if (arg.rfind("omninest://", 0) == 0) {
      if (out_uri != nullptr) {
        *out_uri = arg;
      }
      return true;
    }
  }
  return false;
}

std::string ReadInstanceToken() {
  DWORD required = ::GetEnvironmentVariableW(L"LOCALAPPDATA", nullptr, 0);
  if (required == 0) {
    return {};
  }
  std::wstring local_app_data(required, L'\0');
  DWORD written =
      ::GetEnvironmentVariableW(L"LOCALAPPDATA", local_app_data.data(), required);
  if (written == 0 || written >= required) {
    return {};
  }
  local_app_data.resize(written);
  std::wstring token_path = local_app_data + L"\\OmniNest\\instance.token";
  HANDLE file = ::CreateFileW(
      token_path.c_str(), GENERIC_READ,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return {};
  }
  char buffer[256] = {};
  DWORD bytes_read = 0;
  const BOOL ok = ::ReadFile(file, buffer, sizeof(buffer) - 1, &bytes_read, nullptr);
  ::CloseHandle(file);
  if (!ok || bytes_read == 0) {
    return {};
  }
  std::string token(buffer, bytes_read);
  const auto first = token.find_first_not_of(" \t\r\n");
  if (first == std::string::npos) {
    return {};
  }
  const auto last = token.find_last_not_of(" \t\r\n");
  return token.substr(first, last - first + 1);
}

bool ForwardToRunningInstance(const std::vector<std::string>& args) {
  const std::string token = ReadInstanceToken();
  if (token.empty()) {
    return false;
  }

  WSADATA wsa{};
  if (::WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
    return false;
  }
  SOCKET sock = ::socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (sock == INVALID_SOCKET) {
    ::WSACleanup();
    return false;
  }

  const DWORD timeout_ms = 300;
  ::setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO,
               reinterpret_cast<const char*>(&timeout_ms), sizeof(timeout_ms));
  ::setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO,
               reinterpret_cast<const char*>(&timeout_ms), sizeof(timeout_ms));

  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_port = htons(static_cast<u_short>(kActivatePort));
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

  bool acked = false;
  if (::connect(sock, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == 0) {
    std::string payload = "OMNINEST_ACTIVATE " + token;
    std::string deep_link;
    if (ContainsDeepLink(args, &deep_link)) {
      payload += " " + deep_link;
    }
    payload += "\n";
    const int sent =
        ::send(sock, payload.c_str(), static_cast<int>(payload.size()), 0);
    if (sent == static_cast<int>(payload.size())) {
      std::string response;
      char recv_buf[64] = {};
      while (response.size() < 64) {
        const int n = ::recv(sock, recv_buf, sizeof(recv_buf), 0);
        if (n <= 0) {
          break;
        }
        response.append(recv_buf, static_cast<size_t>(n));
        if (response.find('\n') != std::string::npos) {
          break;
        }
      }
      const auto newline_pos = response.find('\n');
      std::string first_line =
          newline_pos == std::string::npos ? response : response.substr(0, newline_pos);
      if (!first_line.empty() && first_line.back() == '\r') {
        first_line.pop_back();
      }
      acked = (first_line == "OK");
    }
  }
  ::closesocket(sock);
  ::WSACleanup();
  return acked;
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

  // Native mutex prevents engine-level double start; forward activation
  // (and optional deep link) to the running instance, then exit.
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  const DWORD mutex_error = ::GetLastError();
  const bool owns_mutex =
      single_instance_mutex != nullptr && mutex_error != ERROR_ALREADY_EXISTS;
  if (single_instance_mutex != nullptr &&
      mutex_error == ERROR_ALREADY_EXISTS) {
    std::vector<std::string> args = GetCommandLineArguments();
    if (ForwardToRunningInstance(args)) {
      ::CloseHandle(single_instance_mutex);
      ::CoUninitialize();
      return EXIT_SUCCESS;
    }
    // 令牌缺失或对端未回 OK（旧版本/正在退出）：退回正常启动，与 Dart 侧
    // ensureSingleDesktopInstance 的降级策略保持一致，避免用户点图标毫无反应。
  }

  flutter::DartProject project(L"data");

  // Windows 端默认跑 Skia (ANGLE/D3D11)，不启用 Impeller (Vulkan)。
  //
  // Flutter 3.47 起 Windows 默认就是 Impeller。这里反向关掉，是因为实测环境
  // 出现过「启动数秒内共享显存/系统内存冲到 20GB」：Impeller 的
  // `BackdropFilter.grouped` + `ImageFilterConfig` 是较新的路径，配合 30~36σ
  // 全窗口玻璃、动态环境光与 4K 视频壁纸时，每帧离屏回读/模糊金字塔的瞬态
  // 纹理池会堆在 WDDM 共享内存里；同一台机器上 Skia 的 raster 只差约
  // 0.3ms（`docs/2026-11-16/003` §11.1），远小于内存暴涨的代价。
  //
  // 两个方向都保留开关，方便在同一台机器上对照：
  //   OMNINEST_ENABLE_IMPELLER=1   → 重新启用 Impeller（诊断/对比）
  //   OMNINEST_DISABLE_IMPELLER=1  → 显式关闭（默认已是关闭，等价写法）
  {
    // 值只判首字符：`=1` 视为开，`=0` 或空视为关；超长值按「已设置」处理。
    auto env_flag_set = [](const wchar_t* name) {
      wchar_t value[8] = {};
      const DWORD length = ::GetEnvironmentVariableW(name, value, 8);
      return length > 0 && value[0] != L'0';
    };
    if (!env_flag_set(L"OMNINEST_ENABLE_IMPELLER") ||
        env_flag_set(L"OMNINEST_DISABLE_IMPELLER")) {
      project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);
    }
  }

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 800);
  if (!window.Create(L"OmniNest", origin, size)) {
    if (single_instance_mutex != nullptr) {
      if (owns_mutex) {
        ::ReleaseMutex(single_instance_mutex);
      }
      ::CloseHandle(single_instance_mutex);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0) > 0) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (single_instance_mutex != nullptr) {
    if (owns_mutex) {
      ::ReleaseMutex(single_instance_mutex);
    }
    ::CloseHandle(single_instance_mutex);
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
