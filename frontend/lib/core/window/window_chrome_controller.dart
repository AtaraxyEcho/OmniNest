import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:window_manager/window_manager.dart';

class WindowChromeState {
  const WindowChromeState({
    this.immersiveOwner,
    this.isFullscreen = false,
    this.chromeHidden = false,
  });

  final String? immersiveOwner;
  final bool isFullscreen;
  final bool chromeHidden;

  WindowChromeState copyWith({
    Object? immersiveOwner = _sentinel,
    bool? isFullscreen,
    bool? chromeHidden,
  }) {
    return WindowChromeState(
      immersiveOwner:
          identical(immersiveOwner, _sentinel)
              ? this.immersiveOwner
              : immersiveOwner as String?,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      chromeHidden: chromeHidden ?? this.chromeHidden,
    );
  }

  static const _sentinel = Object();
}

enum WindowChromeRequestMode { fullscreen, immersive }

/// 页面级窗口状态租约。释放操作幂等，且只撤销创建该租约的请求。
class WindowChromeLease {
  WindowChromeLease._(this._requestId, this._releaseRequest);

  final int _requestId;
  final void Function(int requestId) _releaseRequest;
  bool _released = false;

  void release() {
    if (_released) {
      return;
    }
    _released = true;
    // 页面 dispose 发生在路由过渡的构建阶段，此处同步修改 Provider 会被
    // Riverpod 的构建期守卫拒绝，导致无边框状态无法退出；延迟一拍执行。
    scheduleMicrotask(() => _releaseRequest(_requestId));
  }
}

final windowChromeControllerProvider =
    NotifierProvider<WindowChromeController, WindowChromeState>(
      WindowChromeController.new,
    );

const _windowFrameChannel = MethodChannel('omninest/window_frame');

class WindowChromeController extends Notifier<WindowChromeState> {
  final Map<int, _WindowChromeRequest> _requests = {};
  int _nextRequestId = 0;
  int _desiredRevision = 0;
  bool _manualFullscreen = false;
  bool _appliedFullscreen = false;
  bool? _appliedChromeHidden;
  bool _resizableApplied = false;
  bool _immersivePlacementSaved = false;
  bool _placementSavePending = false;
  Future<void> _applyQueue = Future<void>.value();

  @override
  WindowChromeState build() {
    return const WindowChromeState();
  }

  WindowChromeLease acquire({
    required String owner,
    required WindowChromeRequestMode mode,
    FutureOr<void> Function()? onExit,
  }) {
    final requestId = ++_nextRequestId;
    final shouldSavePlacement = _requests.isEmpty && !_manualFullscreen;
    _requests[requestId] = _WindowChromeRequest(
      owner: owner,
      mode: mode,
      onExit: onExit,
    );
    if (shouldSavePlacement) {
      _placementSavePending = true;
    }
    _refreshState();
    return WindowChromeLease._(requestId, _releaseRequest);
  }

  WindowChromeLease acquireFullscreen({required String owner}) {
    return acquire(owner: owner, mode: WindowChromeRequestMode.fullscreen);
  }

  WindowChromeLease acquireImmersive({
    required String owner,
    FutureOr<void> Function()? onExit,
  }) {
    return acquire(
      owner: owner,
      mode: WindowChromeRequestMode.immersive,
      onExit: onExit,
    );
  }

  Future<void> requestImmersive({
    required String owner,
    FutureOr<void> Function()? onExit,
  }) async {
    final existing = _requests.entries.where(
      (entry) =>
          entry.value.owner == owner &&
          entry.value.mode == WindowChromeRequestMode.immersive,
    );
    if (existing.isNotEmpty) {
      existing.last.value.onExit = onExit;
      return;
    }
    acquireImmersive(owner: owner, onExit: onExit);
  }

  Future<void> clearImmersive(String owner) async {
    final requestIds = _requests.entries
        .where(
          (entry) =>
              entry.value.owner == owner &&
              entry.value.mode == WindowChromeRequestMode.immersive,
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final requestId in requestIds) {
      _requests.remove(requestId);
    }
    _refreshState();
  }

  Future<void> exitImmersive() async {
    final immersiveEntries = _requests.entries
        .where((entry) => entry.value.mode == WindowChromeRequestMode.immersive)
        .toList(growable: false);
    if (immersiveEntries.isEmpty) {
      _refreshState();
      return;
    }
    final entry = immersiveEntries.last;
    final exit = entry.value.onExit;
    if (exit != null) {
      await exit();
    }
    _releaseRequest(entry.key);
  }

  Future<void> setFullscreen(bool enabled) async {
    _manualFullscreen = enabled;
    _setState(
      state.copyWith(isFullscreen: enabled || state.immersiveOwner != null),
    );
  }

  Future<void> toggleFullscreen() async {
    if (_requests.values.any(
      (request) => request.mode == WindowChromeRequestMode.immersive,
    )) {
      await exitImmersive();
      return;
    }
    await setFullscreen(!state.isFullscreen);
  }

  Future<void> minimize() async {
    if (!isDesktopPlatform) {
      return;
    }
    await windowManager.minimize();
  }

  Future<void> close() async {
    if (!isDesktopPlatform) {
      return;
    }
    await windowManager.close();
  }

  void _setState(WindowChromeState next) {
    // 微任务延迟释放可能在 Provider 容器销毁后触发，禁止已释放回写。
    if (!ref.mounted) {
      return;
    }
    final hidden = next.immersiveOwner != null || next.isFullscreen;
    state = next.copyWith(chromeHidden: hidden);
    final target = state;
    final revision = ++_desiredRevision;
    _applyQueue = _applyQueue.then(
      (_) => _applyChrome(target, revision),
      onError: (Object error, StackTrace stackTrace) {
        if (kDebugMode) {
          debugPrint('Previous window chrome update failed: $error');
        }
        return _applyChrome(target, revision);
      },
    );
    unawaited(_applyQueue);
  }

  void _releaseRequest(int requestId) {
    if (_requests.remove(requestId) == null) {
      return;
    }
    _refreshState();
  }

  void _refreshState() {
    // 微任务延迟释放可能在 Provider 容器销毁后触发，禁止已释放读写。
    if (!ref.mounted) {
      return;
    }
    final latest = _requests.isEmpty ? null : _requests.values.last;
    _setState(
      state.copyWith(
        immersiveOwner: latest?.owner,
        isFullscreen: _manualFullscreen || latest != null,
      ),
    );
  }

  Future<void> _applyChrome(WindowChromeState target, int revision) async {
    if (revision != _desiredRevision) {
      return;
    }
    if (isMobilePlatform) {
      try {
        await SystemChrome.setEnabledSystemUIMode(
          target.chromeHidden
              ? SystemUiMode.immersiveSticky
              : SystemUiMode.edgeToEdge,
        );
      } catch (error) {
        if (kDebugMode && revision == _desiredRevision) {
          debugPrint('System UI update failed: $error');
        }
      }
      return;
    }
    if (!isDesktopPlatform) {
      return;
    }
    if (target.chromeHidden && _placementSavePending) {
      _placementSavePending = false;
      await _saveNativeWindowPlacement();
      if (revision != _desiredRevision) {
        return;
      }
    } else if (!target.chromeHidden) {
      _placementSavePending = false;
    }

    if (defaultTargetPlatform == TargetPlatform.windows) {
      await _applyWindowsChrome(target, revision);
      return;
    }

    if (target.chromeHidden) {
      await _applyHiddenChrome(revision, target.isFullscreen);
    } else {
      await _applyNormalChrome(revision, target.isFullscreen);
    }
    if (revision != _desiredRevision) {
      return;
    }
    if (!target.chromeHidden && !target.isFullscreen) {
      await _restoreNativeWindowPlacement();
      if (revision != _desiredRevision) {
        return;
      }
    }
    // window_manager setResizable writes WS_THICKFRAME without FRAMECHANGED;
    // applying it mid-fullscreen insets the client and exposes white edges.
    // Restore resizable once after returning to windowed chrome.
    if (!target.chromeHidden) {
      await _applyResizableOnce();
    }
  }

  /// Windows: single atomic channel call for border/fullscreen chrome.
  Future<void> _applyWindowsChrome(
    WindowChromeState target,
    int revision,
  ) async {
    try {
      await _windowFrameChannel.invokeMethod<void>(
        'applyWindowChrome',
        <String, dynamic>{
          'hidden': target.chromeHidden,
          'fullscreen': target.isFullscreen,
        },
      );
      _appliedChromeHidden = target.chromeHidden;
      _appliedFullscreen = target.isFullscreen;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Window chrome apply failed: $error');
      }
      return;
    }
    if (revision != _desiredRevision) {
      return;
    }
    // Fullscreen geometry check only; windowed chrome needs no settle sleep
    // because the native call already ForceRedraws.
    if (target.isFullscreen) {
      await _verifyNativeWindowFrame();
      if (revision != _desiredRevision) {
        return;
      }
    }
    if (!target.chromeHidden) {
      await _applyResizableOnce();
    }
  }

  Future<void> _applyHiddenChrome(int revision, bool fullscreen) async {
    await _applyTitleBar(hidden: true, force: true);
    if (revision != _desiredRevision) {
      return;
    }
    await _applyFullscreen(fullscreen);
    if (revision != _desiredRevision) {
      return;
    }
    await _settleNativeWindow();
    if (revision != _desiredRevision) {
      return;
    }
    await _applyTitleBar(hidden: true, force: true);
  }

  Future<void> _applyNormalChrome(int revision, bool fullscreen) async {
    await _applyTitleBar(hidden: false, force: true);
    if (revision != _desiredRevision) {
      return;
    }
    await _applyFullscreen(fullscreen);
    if (revision != _desiredRevision) {
      return;
    }
    await _settleNativeWindow();
    if (revision != _desiredRevision) {
      return;
    }
    await _applyTitleBar(hidden: false, force: true);
  }

  Future<void> _applyFullscreen(bool fullscreen) async {
    if (_appliedFullscreen == fullscreen) {
      return;
    }
    try {
      await _setNativeFullscreen(fullscreen);
      _appliedFullscreen = fullscreen;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Window fullscreen update failed: $error');
      }
    }
  }

  Future<void> _setNativeFullscreen(bool fullscreen) async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      // Windows 必须走自有通道：windowManager.setFullScreen 会激活其插件内
      // 潜伏的 WM_NCCALCSIZE 分支与独立全屏状态（window_manager_plugin.cpp
      // 中 IsFullScreen + title_bar_style 门控），与 runner 的钉扎/动画形成
      // 双路径，禁止回切。
      await _windowFrameChannel.invokeMethod<void>(
        'setWindowFullscreen',
        <String, dynamic>{'fullscreen': fullscreen},
      );
      return;
    }
    await windowManager.setFullScreen(fullscreen);
  }

  Future<void> _applyTitleBar({
    required bool hidden,
    bool force = false,
  }) async {
    if (!force && _appliedChromeHidden == hidden) {
      return;
    }
    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        await _windowFrameChannel.invokeMethod<void>(
          'setFrameHidden',
          <String, dynamic>{'hidden': hidden},
        );
      } else {
        await windowManager.setTitleBarStyle(
          hidden ? TitleBarStyle.hidden : TitleBarStyle.normal,
          windowButtonVisibility: !hidden,
        );
      }
      _appliedChromeHidden = hidden;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Window title bar update failed: $error');
      }
    }
  }

  Future<void> _applyResizableOnce() async {
    if (_resizableApplied) {
      return;
    }
    try {
      await windowManager.setResizable(true);
      _resizableApplied = true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Window resizable update failed: $error');
      }
    }
  }

  Future<void> _settleNativeWindow() async {
    // 等待扩窗后的首帧布局同步；80ms 足以覆盖一帧布局与一次平台回包，
    // 过长会在全屏/退出全屏时造成可感知的停顿。
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await _verifyNativeWindowFrame();
    }
  }

  /// 原生几何断言：全屏窗口矩形贴合显示器、Flutter 子视图填满客户区，
  /// 存在偏差时原生侧直接吸附自愈。
  Future<void> _verifyNativeWindowFrame() async {
    try {
      await _windowFrameChannel.invokeMethod<bool>('verifyWindowFrame');
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Window frame verify failed: $error');
      }
    }
  }

  Future<void> _saveNativeWindowPlacement() async {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }
    try {
      await _windowFrameChannel.invokeMethod<void>('saveWindowPlacement');
      _immersivePlacementSaved = true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Window placement save failed: $error');
      }
    }
  }

  Future<void> _restoreNativeWindowPlacement() async {
    if (defaultTargetPlatform != TargetPlatform.windows ||
        !_immersivePlacementSaved) {
      return;
    }
    try {
      await _windowFrameChannel.invokeMethod<void>('restoreWindowPlacement');
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Window placement restore failed: $error');
      }
    } finally {
      _immersivePlacementSaved = false;
    }
  }

  @visibleForTesting
  Future<void> get pendingApply => _applyQueue;
}

class _WindowChromeRequest {
  _WindowChromeRequest({required this.owner, required this.mode, this.onExit});

  final String owner;
  final WindowChromeRequestMode mode;
  FutureOr<void> Function()? onExit;
}
