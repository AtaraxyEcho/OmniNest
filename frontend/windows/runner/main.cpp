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

bool ForwardToRunningInstance(const std::vector<std::string>& args) {
  WSADATA wsa{};
  if (::WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
    return false;
  }
  SOCKET sock = ::socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (sock == INVALID_SOCKET) {
    ::WSACleanup();
    return false;
  }

  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_port = htons(static_cast<u_short>(kActivatePort));
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

  bool sent = false;
  if (::connect(sock, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == 0) {
    std::string payload = "OMNINEST_ACTIVATE";
    std::string deep_link;
    if (ContainsDeepLink(args, &deep_link)) {
      payload += " " + deep_link;
    }
    payload += "\n";
    ::send(sock, payload.c_str(), static_cast<int>(payload.size()), 0);
    sent = true;
  }
  ::closesocket(sock);
  ::WSACleanup();
  return sent;
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
  if (single_instance_mutex != nullptr &&
      mutex_error == ERROR_ALREADY_EXISTS) {
    std::vector<std::string> args = GetCommandLineArguments();
    ForwardToRunningInstance(args);
    ::CloseHandle(single_instance_mutex);
    ::CoUninitialize();
    return EXIT_SUCCESS;
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
      ::CloseHandle(single_instance_mutex);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (single_instance_mutex != nullptr) {
    ::ReleaseMutex(single_instance_mutex);
    ::CloseHandle(single_instance_mutex);
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
