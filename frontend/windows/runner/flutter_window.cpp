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

void FlutterWindow::SetWindowFrameHidden(bool hidden) {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  if (!normal_window_style_captured_) {
    normal_window_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
    normal_window_ex_style_ = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    normal_window_style_captured_ = true;
  }

  LONG_PTR style = normal_window_style_;
  LONG_PTR ex_style = normal_window_ex_style_;
  if (hidden) {
    style &= ~(WS_CAPTION | WS_THICKFRAME);
    ex_style &= ~(WS_EX_DLGMODALFRAME | WS_EX_CLIENTEDGE | WS_EX_STATICEDGE);
  }

  SetWindowLongPtr(hwnd, GWL_STYLE, style);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                   SWP_NOACTIVATE | SWP_FRAMECHANGED);
  window_frame_hidden_ = hidden;
}

void FlutterWindow::SetWindowFullscreen(bool fullscreen) {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr || window_fullscreen_ == fullscreen) {
    return;
  }
  if (!normal_window_style_captured_) {
    normal_window_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
    normal_window_ex_style_ = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    normal_window_style_captured_ = true;
  }
  if (fullscreen) {
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
    // Flag fullscreen before touching styles so the WM_NCCALCSIZE handler
    // pins client == window rect for this transition and for any style
    // mutation later plugins perform while fullscreen (e.g. a bare
    // WS_THICKFRAME write re-adding the resize border would otherwise inset
    // the client area and expose white edges).
    window_fullscreen_ = true;
    window_frame_hidden_ = true;
    SetWindowLongPtr(hwnd, GWL_STYLE, style);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);
    // Zero the DWM frame margins before expanding so no white edges show up
    // during the transition.
    MARGINS margins = {0, 0, 0, 0};
    DwmExtendFrameIntoClientArea(hwnd, &margins);
    // Apply the frame change at the current rect and lift the window into
    // the topmost band so the taskbar never draws over the expanding window.
    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOOWNERZORDER | SWP_NOACTIVATE |
                     SWP_FRAMECHANGED | SWP_SHOWWINDOW);
    // Expand continuously to the monitor rect instead of snapping, matching
    // the smoothness of the native maximize animation.
    StartFullscreenAnimation(monitor_info.rcMonitor, true);
    return;
  }
  // Clear the fullscreen flag before restoring windowed styles so the
  // default WM_NCCALCSIZE applies the caption/frame insets from here on;
  // keeping the pin active through the restore would leave the client area
  // overlapping the restored title bar.
  window_fullscreen_ = false;
  window_frame_hidden_ = false;
  StopFullscreenAnimation();
  SetWindowLongPtr(hwnd, GWL_STYLE, normal_window_style_);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, normal_window_ex_style_);
  // Shrink continuously back to the saved rect when the placement is a normal
  // restorable window, mirroring the native restore animation; maximized or
  // minimized placements restore immediately.
  if (window_placement_saved_ &&
      saved_window_placement_.showCmd == SW_SHOWNORMAL) {
    // Reapply the frame while still fullscreen-sized so the restored title
    // bar is visible during the shrink, like the native restore animation.
    SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                     SWP_NOACTIVATE | SWP_FRAMECHANGED);
    StartFullscreenAnimation(saved_window_placement_.rcNormalPosition, false);
    return;
  }
  RestoreWindowPlacement();
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                   SWP_NOACTIVATE | SWP_FRAMECHANGED);
}

void FlutterWindow::StartFullscreenAnimation(const RECT& target, bool enter) {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  RECT current = {};
  if (!GetWindowRect(hwnd, &current)) {
    return;
  }
  fullscreen_anim_active_ = true;
  fullscreen_anim_enter_ = enter;
  fullscreen_anim_start_ = current;
  fullscreen_anim_target_ = target;
  fullscreen_anim_start_tick_ = GetTickCount64();
  const bool at_target =
      current.left == target.left && current.top == target.top &&
      current.right == target.right && current.bottom == target.bottom;
  if (at_target) {
    FinishFullscreenAnimation();
    return;
  }
  SetTimer(hwnd, kFullscreenAnimationTimer, 16, nullptr);
  OnFullscreenAnimationTick();
}

void FlutterWindow::OnFullscreenAnimationTick() {
  if (!fullscreen_anim_active_) {
    return;
  }
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    StopFullscreenAnimation();
    return;
  }
  const ULONGLONG elapsed = GetTickCount64() - fullscreen_anim_start_tick_;
  double progress = static_cast<double>(elapsed) / kFullscreenAnimationMs;
  if (progress > 1.0) {
    progress = 1.0;
  }
  // Ease-out cubic: fast start, decelerating settle, like the native
  // maximize motion.
  const double remain = 1.0 - progress;
  const double eased = 1.0 - remain * remain * remain;
  const auto lerp = [eased](LONG from, LONG to) {
    return static_cast<LONG>(from + (to - from) * eased + 0.5);
  };
  const RECT current = {
      lerp(fullscreen_anim_start_.left, fullscreen_anim_target_.left),
      lerp(fullscreen_anim_start_.top, fullscreen_anim_target_.top),
      lerp(fullscreen_anim_start_.right, fullscreen_anim_target_.right),
      lerp(fullscreen_anim_start_.bottom, fullscreen_anim_target_.bottom)};
  SetWindowPos(hwnd, nullptr, current.left, current.top,
               current.right - current.left, current.bottom - current.top,
               SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOACTIVATE |
                   SWP_SHOWWINDOW);
  if (progress >= 1.0) {
    FinishFullscreenAnimation();
  }
}

void FlutterWindow::FinishFullscreenAnimation() {
  StopFullscreenAnimation();
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  if (fullscreen_anim_enter_) {
    const RECT& monitor = fullscreen_anim_target_;
    // Drop out of the topmost band and snap exactly onto the monitor rect.
    SetWindowPos(hwnd, HWND_NOTOPMOST, monitor.left, monitor.top,
                 monitor.right - monitor.left, monitor.bottom - monitor.top,
                 SWP_NOOWNERZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    VerifyWindowFrame();
    return;
  }
  RestoreWindowPlacement();
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                   SWP_NOACTIVATE | SWP_FRAMECHANGED);
}

void FlutterWindow::StopFullscreenAnimation() {
  if (!fullscreen_anim_active_) {
    return;
  }
  fullscreen_anim_active_ = false;
  HWND hwnd = GetHandle();
  if (hwnd != nullptr) {
    KillTimer(hwnd, kFullscreenAnimationTimer);
  }
}

bool FlutterWindow::VerifyWindowFrame() {
  if (!window_fullscreen_ || fullscreen_anim_active_) {
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
  bool adjusted = false;
  const RECT& monitor = monitor_info.rcMonitor;
  RECT window_rect = {};
  if (GetWindowRect(hwnd, &window_rect) &&
      (window_rect.left != monitor.left || window_rect.top != monitor.top ||
       window_rect.right != monitor.right ||
       window_rect.bottom != monitor.bottom)) {
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
      if (GetWindowRect(child, &child_rect) &&
          (child_rect.left != origin.x || child_rect.top != origin.y ||
           child_rect.right != origin.x + client.right ||
           child_rect.bottom != origin.y + client.bottom)) {
        MoveWindow(child, 0, 0, client.right, client.bottom, TRUE);
        adjusted = true;
      }
    }
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
                   SWP_NOACTIVATE | SWP_FRAMECHANGED);
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
    case WM_NCCALCSIZE:
      // While fullscreen, pin the client area to the full window rect so no
      // style change (resize border re-added by any code path) can inset the
      // client area and expose white edges around the Flutter view.
      if (window_fullscreen_ && wparam) {
        return 0;
      }
      break;
    case WM_TIMER:
      // Drive the borderless fullscreen transition from the UI thread; the
      // animation must not block the platform thread or Flutter's WM_SIZE
      // dispatch would stall and the content would jump instead of scaling.
      if (wparam == kFullscreenAnimationTimer) {
        OnFullscreenAnimationTick();
        return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
