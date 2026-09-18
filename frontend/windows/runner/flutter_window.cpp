#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <dwmapi.h>
#include <optional>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr const char kWindowFrameChannel[] = "omninest/window_frame";
constexpr const char kSetFrameHiddenMethod[] = "setFrameHidden";
constexpr const char kSetWindowFullscreenMethod[] = "setWindowFullscreen";
constexpr const char kApplyWindowChromeMethod[] = "applyWindowChrome";
constexpr const char kSaveWindowPlacementMethod[] = "saveWindowPlacement";
constexpr const char kRestoreWindowPlacementMethod[] = "restoreWindowPlacement";
constexpr const char kVerifyWindowFrameMethod[] = "verifyWindowFrame";
constexpr const char kShowWindowMethod[] = "showWindow";
constexpr const char kIsWindowFullscreenMethod[] = "isWindowFullscreen";
constexpr const char kFinishTrayMenuPopupMethod[] = "finishTrayMenuPopup";
constexpr const char kHiddenArgument[] = "hidden";
constexpr const char kFullscreenArgument[] = "fullscreen";
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
  window_frame_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kWindowFrameChannel,
          &flutter::StandardMethodCodec::GetInstance());
  window_frame_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == kApplyWindowChromeMethod) {
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments == nullptr) {
            result->Error("bad_args", "chrome arguments are required");
            return;
          }
          const auto hidden_entry =
              arguments->find(flutter::EncodableValue(kHiddenArgument));
          const auto fullscreen_entry =
              arguments->find(flutter::EncodableValue(kFullscreenArgument));
          if (hidden_entry == arguments->end() ||
              fullscreen_entry == arguments->end()) {
            result->Error("bad_args", "hidden and fullscreen are required");
            return;
          }
          const auto* hidden = std::get_if<bool>(&hidden_entry->second);
          const auto* fullscreen =
              std::get_if<bool>(&fullscreen_entry->second);
          if (hidden == nullptr || fullscreen == nullptr) {
            result->Error("bad_args", "hidden and fullscreen must be bool");
            return;
          }
          ApplyWindowChrome(*hidden, *fullscreen);
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (call.method_name() != kSetFrameHiddenMethod) {
          if (call.method_name() == kShowWindowMethod) {
            // ShowWindowAsync may be silently dropped for a window created
            // hidden; show synchronously here on the UI thread instead.
            ::ShowWindow(GetHandle(), SW_SHOW);
            ::SetForegroundWindow(GetHandle());
            result->Success(flutter::EncodableValue(true));
            return;
          }
          if (call.method_name() == kIsWindowFullscreenMethod) {
            result->Success(flutter::EncodableValue(window_fullscreen_));
            return;
          }
          if (call.method_name() == kFinishTrayMenuPopupMethod) {
            // KB135788: after TrackPopupMenu returns, the menu owner window
            // must receive a WM_NULL, otherwise the next tray click can
            // dismiss the freshly opened menu immediately.
            ::PostMessage(GetHandle(), WM_NULL, 0, 0);
            result->Success(flutter::EncodableValue(true));
            return;
          }
          if (call.method_name() == kSaveWindowPlacementMethod) {
            SaveWindowPlacement();
            result->Success(flutter::EncodableValue(true));
            return;
          }
          if (call.method_name() == kRestoreWindowPlacementMethod) {
            RestoreWindowPlacement();
            result->Success(flutter::EncodableValue(true));
            return;
          }
          if (call.method_name() == kVerifyWindowFrameMethod) {
            result->Success(flutter::EncodableValue(VerifyWindowFrame()));
            return;
          }
          if (call.method_name() == kSetWindowFullscreenMethod) {
            const auto* arguments =
                std::get_if<flutter::EncodableMap>(call.arguments());
            if (arguments == nullptr) {
              result->Error("bad_args", "fullscreen argument is required");
              return;
            }
            const auto fullscreen_entry =
                arguments->find(flutter::EncodableValue(kFullscreenArgument));
            if (fullscreen_entry == arguments->end()) {
              result->Error("bad_args", "fullscreen argument is required");
              return;
            }
            const auto* fullscreen =
                std::get_if<bool>(&fullscreen_entry->second);
            if (fullscreen == nullptr) {
              result->Error("bad_args", "fullscreen argument must be a bool");
              return;
            }
            SetWindowFullscreen(*fullscreen);
            result->Success(flutter::EncodableValue(true));
            return;
          }
          result->NotImplemented();
          return;
        }
        const auto* arguments =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (arguments == nullptr) {
          result->Error("bad_args", "hidden argument is required");
          return;
        }
        const auto hidden_entry =
            arguments->find(flutter::EncodableValue(kHiddenArgument));
        if (hidden_entry == arguments->end()) {
          result->Error("bad_args", "hidden argument is required");
          return;
        }
        const auto* hidden = std::get_if<bool>(&hidden_entry->second);
        if (hidden == nullptr) {
          result->Error("bad_args", "hidden argument must be a bool");
          return;
        }
        SetWindowFrameHidden(*hidden);
        result->Success(flutter::EncodableValue(true));
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // The window starts hidden (see Win32Window::Show) and is shown by
  // window_manager after Dart applies the remembered geometry. The template's
  // next-frame auto-show must be removed here, otherwise it re-hides the
  // window with SW_HIDE right after Dart shows it. ForceRedraw keeps a frame
  // pending so the first paint is ready when the window is revealed.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_frame_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::CaptureNormalStylesIfNecessary() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr || normal_window_style_captured_) {
    return;
  }
  normal_window_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
  normal_window_ex_style_ = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  normal_window_style_captured_ = true;
}

void FlutterWindow::ForceFlutterRedraw() {
  if (flutter_controller_) {
    flutter_controller_->ForceRedraw();
    if (flutter_controller_->view()) {
      HWND child = flutter_controller_->view()->GetNativeWindow();
      if (child != nullptr) {
        ::SetFocus(child);
      }
    }
  }
}

void FlutterWindow::SyncFlutterViewChild() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr || !flutter_controller_ || !flutter_controller_->view()) {
    return;
  }
  HWND child = flutter_controller_->view()->GetNativeWindow();
  if (child == nullptr) {
    return;
  }
  RECT client = {};
  if (!GetClientRect(hwnd, &client)) {
    return;
  }
  const int width = client.right - client.left;
  const int height = client.bottom - client.top;
  if (width <= 0 || height <= 0) {
    return;
  }
  RECT child_rect = {};
  if (!GetWindowRect(child, &child_rect)) {
    return;
  }
  if (child_rect.right - child_rect.left != width ||
      child_rect.bottom - child_rect.top != height) {
    MoveWindow(child, 0, 0, width, height, TRUE);
  }
}

void FlutterWindow::ApplyWindowChrome(bool hidden, bool fullscreen) {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  CaptureNormalStylesIfNecessary();

  // Immersive fullscreen: one style write and one monitor snap. Do not split
  // into frameHidden/fullscreen steps, which rewrites caption mid-transition
  // and double-fires SetWindowPos.
  if (hidden && fullscreen) {
    if (!window_placement_saved_) {
      SaveWindowPlacement();
    }
    MONITORINFO monitor_info = {};
    monitor_info.cbSize = sizeof(MONITORINFO);
    if (!GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                        &monitor_info)) {
      return;
    }
    LONG_PTR style = normal_window_style_;
    LONG_PTR ex_style = normal_window_ex_style_;
    style &= ~(WS_CAPTION | WS_THICKFRAME | WS_BORDER | WS_DLGFRAME);
    style |= WS_POPUP;
    ex_style &= ~(WS_EX_DLGMODALFRAME | WS_EX_CLIENTEDGE | WS_EX_STATICEDGE |
                  WS_EX_WINDOWEDGE);
    // Flag before style writes so WM_NCCALCSIZE pins client == window.
    window_fullscreen_ = true;
    window_frame_hidden_ = true;
    SetWindowLongPtr(hwnd, GWL_STYLE, style);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);
    MARGINS margins = {0, 0, 0, 0};
    DwmExtendFrameIntoClientArea(hwnd, &margins);
    const RECT& monitor = monitor_info.rcMonitor;
    RECT current = {};
    const bool geometry_matches =
        GetWindowRect(hwnd, &current) && current.left == monitor.left &&
        current.top == monitor.top && current.right == monitor.right &&
        current.bottom == monitor.bottom;
    if (geometry_matches) {
      // Already snapped to the monitor rect (e.g. re-entering fullscreen while
      // fullscreen): replay only the frame change. Skipping the size move
      // avoids a Flutter surface rebuild and its black-frame gap.
      SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOOWNERZORDER |
                       SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOCOPYBITS);
    } else {
      // SWP_NOCOPYBITS: do not blit stale pre-fullscreen bits into the new
      // surface (classic black/white flash source on size-preserving copies).
      SetWindowPos(hwnd, HWND_TOP, monitor.left, monitor.top,
                   monitor.right - monitor.left, monitor.bottom - monitor.top,
                   SWP_NOOWNERZORDER | SWP_FRAMECHANGED | SWP_SHOWWINDOW |
                       SWP_NOCOPYBITS);
    }
    SyncFlutterViewChild();
    DwmFlush();
    ForceFlutterRedraw();
    return;
  }

  // Windowed chrome (normal frame or frameless non-fullscreen).
  window_fullscreen_ = false;
  window_frame_hidden_ = hidden;
  if (hidden) {
    LONG_PTR style = normal_window_style_;
    style &= ~(WS_CAPTION | WS_THICKFRAME);
    LONG_PTR ex_style = normal_window_ex_style_;
    ex_style &= ~(WS_EX_DLGMODALFRAME | WS_EX_CLIENTEDGE | WS_EX_STATICEDGE);
    SetWindowLongPtr(hwnd, GWL_STYLE, style);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);
  } else {
    SetWindowLongPtr(hwnd, GWL_STYLE, normal_window_style_);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, normal_window_ex_style_);
  }
  if (!hidden && window_placement_saved_) {
    RestoreWindowPlacement();
  } else {
    SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                     SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_NOCOPYBITS);
  }
  SyncFlutterViewChild();
  DwmFlush();
  ForceFlutterRedraw();
}

void FlutterWindow::SetWindowFrameHidden(bool hidden) {
  ApplyWindowChrome(hidden, window_fullscreen_);
}

void FlutterWindow::SetWindowFullscreen(bool fullscreen) {
  ApplyWindowChrome(window_frame_hidden_ || fullscreen, fullscreen);
}

bool FlutterWindow::VerifyWindowFrame() {
  if (!window_fullscreen_) {
    return false;
  }
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return false;
  }
  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(MONITORINFO);
  if (!GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                      &monitor_info)) {
    return false;
  }
  // 2px tolerance: an extra SetWindowPos/MoveWindow for a 1px DPI residue
  // forces another Flutter surface resize and a visible black frame.
  constexpr LONG kGeometryTolerance = 2;
  auto differs = [](LONG a, LONG b) {
    const LONG delta = a > b ? a - b : b - a;
    return delta > kGeometryTolerance;
  };
  bool adjusted = false;
  const RECT& monitor = monitor_info.rcMonitor;
  RECT window_rect = {};
  if (GetWindowRect(hwnd, &window_rect) &&
      (differs(window_rect.left, monitor.left) ||
       differs(window_rect.top, monitor.top) ||
       differs(window_rect.right, monitor.right) ||
       differs(window_rect.bottom, monitor.bottom))) {
    SetWindowPos(hwnd, HWND_TOP, monitor.left, monitor.top,
                 monitor.right - monitor.left, monitor.bottom - monitor.top,
                 SWP_NOOWNERZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    adjusted = true;
  }
  if (flutter_controller_ && flutter_controller_->view()) {
    HWND child = flutter_controller_->view()->GetNativeWindow();
    RECT client = {};
    if (child != nullptr && GetClientRect(hwnd, &client)) {
      POINT origin = {0, 0};
      ClientToScreen(hwnd, &origin);
      RECT child_rect = {};
      const LONG expected_right = origin.x + client.right;
      const LONG expected_bottom = origin.y + client.bottom;
      if (GetWindowRect(child, &child_rect) &&
          (differs(child_rect.left, origin.x) ||
           differs(child_rect.top, origin.y) ||
           differs(child_rect.right, expected_right) ||
           differs(child_rect.bottom, expected_bottom))) {
        MoveWindow(child, 0, 0, client.right, client.bottom, TRUE);
        adjusted = true;
      }
    }
  }
  if (adjusted) {
    DwmFlush();
    ForceFlutterRedraw();
  }
  return adjusted;
}

void FlutterWindow::SaveWindowPlacement() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  WINDOWPLACEMENT placement = {};
  placement.length = sizeof(WINDOWPLACEMENT);
  if (GetWindowPlacement(hwnd, &placement)) {
    saved_window_placement_ = placement;
    window_placement_saved_ = true;
  }
}

void FlutterWindow::RestoreWindowPlacement() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr || !window_placement_saved_) {
    return;
  }
  saved_window_placement_.length = sizeof(WINDOWPLACEMENT);
  SetWindowPlacement(hwnd, &saved_window_placement_);
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                   SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_NOCOPYBITS);
  window_placement_saved_ = false;
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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_ERASEBKGND: {
      // Fill the client area with black before returning so DefWindowProc
      // erase does not flash white between frames during resize/maximize.
      auto* hdc = reinterpret_cast<HDC>(wparam);
      RECT client = {};
      if (hdc != nullptr && GetClientRect(hwnd, &client)) {
        HBRUSH brush = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
        FillRect(hdc, &client, brush);
      }
      return 1;
    }
    case WM_SIZE: {
      // Parent MoveWindow keeps child_content_ in place; then re-assert the
      // Flutter view fills the client after maximize/restore/frameless snaps.
      const LRESULT size_result =
          Win32Window::MessageHandler(hwnd, message, wparam, lparam);
      if (window_frame_hidden_ || wparam == SIZE_MAXIMIZED ||
          wparam == SIZE_RESTORED) {
        SyncFlutterViewChild();
      }
      return size_result;
    }
    case WM_GETMINMAXINFO: {
      // Frameless maximized window: pin the max rect to the work area so it
      // does not grow under the taskbar and get pulled back by NCCALCSIZE.
      if (window_frame_hidden_ && !window_fullscreen_) {
        auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
        MONITORINFO monitor_info = {};
        monitor_info.cbSize = sizeof(MONITORINFO);
        if (GetMonitorInfo(
                MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                &monitor_info)) {
          const RECT& work = monitor_info.rcWork;
          const RECT& monitor = monitor_info.rcMonitor;
          info->ptMaxPosition.x = work.left - monitor.left;
          info->ptMaxPosition.y = work.top - monitor.top;
          info->ptMaxSize.x = work.right - work.left;
          info->ptMaxSize.y = work.bottom - work.top;
        }
      }
      break;
    }
    case WM_NCCALCSIZE:
      // Frameless (fullscreen or immersive windowed): pin the client area to
      // the full window rect. Without this, maximize/style switches can inset
      // the client and leave black/white bands around the Flutter view.
      if (window_frame_hidden_ && wparam) {
        return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
