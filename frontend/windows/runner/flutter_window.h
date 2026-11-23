#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <optional>

#include "win32_window.h"

#include <shellapi.h>

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void SetWindowFrameHidden(bool hidden);
  void SetWindowFullscreen(bool fullscreen);
  /// Atomic border/fullscreen switch: one style write and one SetWindowPos
  /// to avoid repeated FRAMECHANGED/WM_SIZE causing long black frames.
  void ApplyWindowChrome(bool hidden, bool fullscreen);
  void SetThemeBrightness(bool is_dark);
  void CaptureNormalStylesIfNecessary();
  void SaveWindowPlacement();
  void RestoreWindowPlacement();
  bool VerifyWindowFrame();
  void ForceFlutterRedraw();
  // Align the Flutter child view to the current client rect after frameless
  // or fullscreen chrome switches, so no black bands remain.
  void SyncFlutterViewChild();
  // Fill the client area the Flutter child has not covered yet while the
  // native modal sizing loop runs, so live resize never exposes white.
  void PaintSizingGap(HWND hwnd);
  COLORREF ResolveSizingGapColor() const;
  HBRUSH EnsureSizingGapBrush();
  void ResetSizingBrush();
  void RefreshTaskbarAutoHideState();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_frame_channel_;

  LONG_PTR normal_window_style_ = 0;
  LONG_PTR normal_window_ex_style_ = 0;
  bool normal_window_style_captured_ = false;
  bool window_frame_hidden_ = false;
  bool window_fullscreen_ = false;
  WINDOWPLACEMENT saved_window_placement_ = {};
  bool window_placement_saved_ = false;
  // True only between WM_ENTERSIZEMOVE and WM_EXITSIZEMOVE. The dark/light
  // gap fill is confined to the modal sizing loop so maximize/fullscreen
  // paths keep their existing no-erase behaviour.
  bool sizing_move_active_ = false;
  // App-driven theme brightness (true = light, false = dark). Before Dart
  // pushes a theme, PaintSizingGap falls back to Windows AppsUseLightTheme.
  std::optional<bool> app_light_theme_;
  HBRUSH sizing_gap_brush_ = nullptr;
  // Cached taskbar auto-hide state refreshed only on creation and system
  // settings/display changes so WM_NCCALCSIZE never blocks on SHAppBarMessage.
  bool taskbar_auto_hide_ = false;
  UINT taskbar_edge_ = ABE_BOTTOM;
  // Set by requestAppExit so WM_CLOSE bypasses plugin/Flutter interception and
  // destroys the window directly.
  bool exiting_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
