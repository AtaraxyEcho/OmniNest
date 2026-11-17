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
  ResetSizingBrush();
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
    // Repaint = FALSE: the view is resized, but the compositor keeps showing
    // the previous frame until Flutter presents the next one. Repainting here
    // would ask for a paint before the engine has a frame at the new size,
    // which is what made live-resize and maximize blink black.
    MoveWindow(child, 0, 0, width, height, FALSE);
  }
}

void FlutterWindow::ResetSizingBrush() {
  if (sizing_gap_brush_ != nullptr) {
    DeleteObject(sizing_gap_brush_);
    sizing_gap_brush_ = nullptr;
  }
}

void FlutterWindow::PaintSizingGap(HWND hwnd) {
  if (!sizing_move_active_ || !flutter_controller_ ||
      !flutter_controller_->view()) {
    return;
  }
  HWND child = flutter_controller_->view()->GetNativeWindow();
  if (child == nullptr) {
    return;
  }
  RECT client = {};
  RECT child_rect = {};
  if (!GetClientRect(hwnd, &client) || !GetWindowRect(child, &child_rect)) {
    return;
  }
  POINT origin = {0, 0};
  ClientToScreen(hwnd, &origin);
  const LONG covered_right = child_rect.right - origin.x;
  const LONG covered_bottom = child_rect.bottom - origin.y;
  if (covered_right >= client.right && covered_bottom >= client.bottom) {
    return;
  }
  if (sizing_gap_brush_ == nullptr) {
    // 与桌面皮肤 --bg 同源（palette bgDark/bgLight）；按系统主题取色，
    // 浅色档露出浅底而不是黑带。读一次缓存到循环结束。
    DWORD light_mode = 1;
    DWORD size = sizeof(light_mode);
    RegGetValue(HKEY_CURRENT_USER,
                L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\"
                L"Personalize",
                L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light_mode,
                &size);
    const COLORREF color =
        light_mode == 0 ? RGB(11, 14, 17) : RGB(238, 240, 236);
    sizing_gap_brush_ = CreateSolidBrush(color);
  }
  HDC dc = GetDC(hwnd);
  if (dc == nullptr) {
    return;
  }
  // 只填子窗口没盖住的右/下两条，避免整幅客户区重绘与子窗口内容打架。
  if (covered_right < client.right) {
    RECT strip = {covered_right, 0, client.right, client.bottom};
    FillRect(dc, &strip, sizing_gap_brush_);
  }
  if (covered_bottom < client.bottom) {
    RECT strip = {0, covered_bottom, covered_right, client.bottom};
    FillRect(dc, &strip, sizing_gap_brush_);
  }
  ReleaseDC(hwnd, dc);
}

namespace {
// Win11 给每个窗口描一条 1px 边框，深色自绘窗口上就是一圈白边。
// DWMWA_BORDER_COLOR(34) 取 DWMWA_COLOR_NONE(0xFFFFFFFE) 可关掉它；
// 恢复带框窗口时再置回 DWMWA_COLOR_DEFAULT(0xFFFFFFFF)。
constexpr DWORD kDwmwaBorderColor = 34;
constexpr DWORD kDwmColorNone = 0xFFFFFFFE;
constexpr DWORD kDwmColorDefault = 0xFFFFFFFF;

#ifndef WM_THEMECHANGED
#define WM_THEMECHANGED 0x031A
#endif

bool SetDwmBorderVisible(HWND hwnd, bool visible) {
  DWORD color = visible ? kDwmColorDefault : kDwmColorNone;
  return SUCCEEDED(
      DwmSetWindowAttribute(hwnd, kDwmwaBorderColor, &color, sizeof(color)));
}

// DWMWA_BORDER_COLOR 只在 Win11 22000+ 生效，旧系统上属性写入会失败。
// 此时靠零边距扩展帧 + NCCALCSIZE 钉扎客户区 + 抑制 WM_NCPAINT，让系统
// 没有非客户区可描。窗口激活、DPI/主题变化都会让 DWM 重绘并重置边框色，
// 所以每次 NC 重绘机会都重新声明一次，而不是只在切换样式时下发。
void ReassertFramelessBorder(HWND hwnd) {
  if (!SetDwmBorderVisible(hwnd, false)) {
    MARGINS margins = {0, 0, 0, 0};
    DwmExtendFrameIntoClientArea(hwnd, &margins);
  }
}

// 无边框窗口保留了 WS_THICKFRAME，系统默认的最大化矩形是「显示器 + 一圈
// 边框」，而 WM_NCCALCSIZE 已把客户区钉成整个窗口矩形，于是最大化后内容
// 会被显示器裁掉一圈。这里把最大矩形钉回工作区。
void PinMaximizedRectToWorkArea(HWND hwnd, MINMAXINFO* info) {
  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(MONITORINFO);
  if (!GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                      &monitor_info)) {
    return;
  }
  const RECT& work = monitor_info.rcWork;
  const RECT& monitor = monitor_info.rcMonitor;
  info->ptMaxPosition.x = work.left - monitor.left;
  info->ptMaxPosition.y = work.top - monitor.top;
  info->ptMaxSize.x = work.right - work.left;
  info->ptMaxSize.y = work.bottom - work.top;
}
}  // namespace

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
    ReassertFramelessBorder(hwnd);
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
      // SWP_NOCOPYBITS: window position and size both change in one step, so
      // a blit would anchor the windowed frame at the monitor origin with a
      // black L-shaped growth for the uncovered regions; device testing read
      // that as a visible jump in the quiet moment after the route transition.
      // A uniform black gap for the few frames of the surface rebuild is
      // cleaner and is masked by the entry scale animation.
      SetWindowPos(hwnd, HWND_TOP, monitor.left, monitor.top,
                   monitor.right - monitor.left, monitor.bottom - monitor.top,
                   SWP_NOOWNERZORDER | SWP_FRAMECHANGED | SWP_SHOWWINDOW |
                       SWP_NOCOPYBITS);
    }
    SyncFlutterViewChild();
    // Do not DwmFlush here: the flush blocks the platform thread (and the
    // method-channel reply) until DWM composition finishes, which can take
    // 1-2s while the Flutter surface rebuilds. ForceFlutterRedraw already
    // queues the next frame; callers must not await presentation.
    ForceFlutterRedraw();
    return;
  }

  // Windowed chrome (normal frame or frameless non-fullscreen).
  window_fullscreen_ = false;
  window_frame_hidden_ = hidden;
  if (hidden) {
    LONG_PTR style = normal_window_style_;
    // 描边要剥（WS_BORDER/WS_DLGFRAME 留下的细线就是那圈白边），但
    // WS_THICKFRAME 必须留着：系统正是靠它判断"这个窗口可以缩放"，
    // 缩放的模态循环（WM_NCLBUTTONDOWN + HTLEFT/…）才会启动。视觉上
    // 看不到边框，是因为 WM_NCCALCSIZE 把客户区钉成了整个窗口。
    style &= ~(WS_CAPTION | WS_BORDER | WS_DLGFRAME);
    style |= WS_THICKFRAME;
    LONG_PTR ex_style = normal_window_ex_style_;
    ex_style &= ~(WS_EX_DLGMODALFRAME | WS_EX_CLIENTEDGE | WS_EX_STATICEDGE |
                  WS_EX_WINDOWEDGE);
    SetWindowLongPtr(hwnd, GWL_STYLE, style);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);
    MARGINS margins = {0, 0, 0, 0};
    DwmExtendFrameIntoClientArea(hwnd, &margins);
  } else {
    SetWindowLongPtr(hwnd, GWL_STYLE, normal_window_style_);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, normal_window_ex_style_);
  }
  if (hidden) {
    ReassertFramelessBorder(hwnd);
  } else {
    SetDwmBorderVisible(hwnd, true);
  }
  if (!hidden && window_placement_saved_) {
    RestoreWindowPlacement();
  } else {
    SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                     SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_NOCOPYBITS);
  }
  SyncFlutterViewChild();
  // See immersive path: never block the platform thread on DWM composition.
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
    // Geometry self-heal already re-asserted the frame; do not block on DWM.
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
  // window_manager 注册的顶层 WndProc 委托先于本函数运行，而它对
  // WM_GETMINMAXINFO 无条件 return 0（只写 min/max track 尺寸）。照常规
  // 早退会让下面的工作区钉扎永远不执行；且旧写法 break 到 DefWindowProc
  // 还会把刚钉好的 ptMaxPosition/ptMaxSize 覆盖回系统默认值。这里先让插件
  // 写完 track，再补钉扎并直接返回，两份约束都保留。
  if (message == WM_GETMINMAXINFO && window_frame_hidden_ &&
      !window_fullscreen_) {
    if (flutter_controller_) {
      flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                    lparam);
    }
    PinMaximizedRectToWorkArea(hwnd, reinterpret_cast<MINMAXINFO*>(lparam));
    return 0;
  }

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
    case WM_NCACTIVATE:
      // 失焦/聚焦的第一条消息就是它（早于 WM_ACTIVATE）。插件只在
      // title_bar_style=="hidden" 或 is_frameless 时才 return 1，而本项目
      // 的无边框走自有通道、插件状态恒为 normal/false，于是这条消息一路
      // 落到 DefWindowProc 去重绘非客户区——那圈白边正是这里画出来的。
      // 自己接管：重申边框色后返回 TRUE，禁止系统重绘 NC 帧。
      if (window_frame_hidden_) {
        ReassertFramelessBorder(hwnd);
        return 1;
      }
      break;
    case WM_ENTERSIZEMOVE:
      // 拖边缩放走系统的模态循环，期间不再发 WM_ACTIVATE；进入/退出循环
      // 时 DWM 会重新评估帧，只在这两个边界重申，避免每步鼠标移动都做一次
      // DWM 属性写入反而拖慢缩放。
      sizing_move_active_ = true;
      if (window_frame_hidden_) {
        ReassertFramelessBorder(hwnd);
      }
      break;
    case WM_EXITSIZEMOVE:
      sizing_move_active_ = false;
      ResetSizingBrush();
      if (window_frame_hidden_) {
        ReassertFramelessBorder(hwnd);
      }
      SyncFlutterViewChild();
      break;
    case WM_WINDOWPOSCHANGED: {
      const auto* pos = reinterpret_cast<const WINDOWPOS*>(lparam);
      if (window_frame_hidden_ && (pos->flags & SWP_FRAMECHANGED) != 0) {
        ReassertFramelessBorder(hwnd);
      }
      break;
    }
    case WM_ACTIVATE:
    case WM_DPICHANGED:
    case WM_THEMECHANGED:
    case WM_DWMCOLORIZATIONCOLORCHANGED:
      // 点击窗口、切换 DPI/主题都会让 DWM 重绘非客户区并重置边框色，
      // 这正是「点一下冒出一圈白边」的时机。break 后仍交给基类处理
      // SetFocus / 几何更新 / 沉浸式深色模式。
      if (window_frame_hidden_) {
        ReassertFramelessBorder(hwnd);
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_ERASEBKGND:
      // Never erase. Filling the client first turned every live-resize step
      // and every maximize/restore into a black frame: the window painted
      // black, then waited for Flutter to present. Returning handled leaves
      // the previous frame on screen until the next one is composed.
      return 1;
    case WM_NCPAINT:
      // Frameless windows have no non-client area to paint; letting
      // DefWindowProc run would redraw the frame we just removed.
      if (window_frame_hidden_) {
        return 0;
      }
      break;
    case WM_SIZE: {
      // 模态缩放循环里引擎来不及按新尺寸出帧，子窗口会滞后于客户区；
      // 露出的那条不填就是白边（实测 255,255,255）。只在循环内填主题底色。
      //
      // 顺序不能颠倒：`Win32Window::MessageHandler` 内部会
      // `MoveWindow(child_content_, …, width, height, FALSE)` 把子窗口拉到
      // 新客户区尺寸，之后再调本函数时 `covered_right/bottom` 恒等于
      // `client.right/bottom`，函数会在第一个 if 处直接返回——补缝一行都
      // 没画过，这就是拖边放大时右/下缘那圈残影。必须先按子窗口**当前**
      // （尚未扩大的）矩形把新增暴露带铺上主题底色，再让基类去挪子窗口。
      PaintSizingGap(hwnd);
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
    case WM_NCHITTEST: {
      // Frameless windowed: styles were stripped, so the OS no longer offers
      // resize borders. Hand back the eight grips ourselves, otherwise a
      // frameless window can never be resized by its edges.
      if (!window_frame_hidden_ || window_fullscreen_) {
        break;
      }
      RECT rect;
      if (!GetWindowRect(hwnd, &rect)) {
        break;
      }
      // 不用 GET_X_LPARAM：它来自 windowsx.h，本文件没有包含该头。
      POINT cursor{static_cast<short>(LOWORD(lparam)),
                   static_cast<short>(HIWORD(lparam))};
      constexpr int kGrip = 6;
      const bool left = cursor.x < rect.left + kGrip;
      const bool right = cursor.x >= rect.right - kGrip;
      const bool top = cursor.y < rect.top + kGrip;
      const bool bottom = cursor.y >= rect.bottom - kGrip;
      if (top && left) return HTTOPLEFT;
      if (top && right) return HTTOPRIGHT;
      if (bottom && left) return HTBOTTOMLEFT;
      if (bottom && right) return HTBOTTOMRIGHT;
      if (left) return HTLEFT;
      if (right) return HTRIGHT;
      if (top) return HTTOP;
      if (bottom) return HTBOTTOM;
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
