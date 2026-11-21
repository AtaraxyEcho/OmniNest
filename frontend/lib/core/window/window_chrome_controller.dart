import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:window_manager/window_manager.dart';
import 'package:omninest/core/log/dev_log.dart';

/// 窗口八向缩放方向（与 window_manager 的 ResizeEdge 一一对应）。
enum WindowResizeEdge {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

class WindowChromeState {
  const WindowChromeState({
    this.immersiveOwner,
    this.isFullscreen = false,
    this.chromeHidden = false,
    this.isMaximized = false,
  });

  final String? immersiveOwner;
  final bool isFullscreen;
  final bool chromeHidden;

  /// 原生窗口当前是否最大化。
  ///
  /// 自绘标题栏的中键要按这个值在「最大化 / 还原」字形之间切换（样例
  /// `Shell.tsx:64`）；拖到屏幕边缘由系统直接最大化时也要跟上。
  final bool isMaximized;

  WindowChromeState copyWith({
    Object? immersiveOwner = _sentinel,
    bool? isFullscreen,
    bool? chromeHidden,
    bool? isMaximized,
  }) {
    return WindowChromeState(
      immersiveOwner:
          identical(immersiveOwner, _sentinel)
              ? this.immersiveOwner
              : immersiveOwner as String?,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      chromeHidden: chromeHidden ?? this.chromeHidden,
      isMaximized: isMaximized ?? this.isMaximized,
    );
  }

  static const _sentinel = Object();
}

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

/// 启动阶段直接下发无边框样式，返回是否确认生效。
///
/// 此时还没有 Provider 容器（[WindowChromeController] 建不起来），而首帧
/// 之前就必须把原生标题栏与描边去掉：等壳层挂载再切，登录页会先带一圈
/// 系统边框露出来。Windows 走自有通道，其余桌面平台用 window_manager。
///
/// 引擎启动早期通道可能尚未注册，单次 invokeMethod 会抛异常；原实现静默
/// 吞掉后回落到 window_manager，而 ensureInitialized 在另一个并行启动任务
/// 里往往还没跑完，结果是「窗口已显示、系统描边仍在」。这里有限重试并把
/// 结果交给调用方，好在展示窗口之前再兜一次。
const int _chromeApplyAttempts = 3;

Future<bool> applyFramelessWindowChrome() async {
  if (!isDesktopPlatform) {
    return true;
  }
  if (defaultTargetPlatform == TargetPlatform.windows) {
    for (var attempt = 0; attempt < _chromeApplyAttempts; attempt++) {
      try {
        await _windowFrameChannel.invokeMethod<void>(
          'applyWindowChrome',
          <String, dynamic>{'hidden': true, 'fullscreen': false},
        );
        return true;
      } on Object catch (error) {
        if (kDebugMode) {
          devLog('窗口无边框下发失败（第 ${attempt + 1} 次）: ${error.runtimeType}');
        }
        if (attempt + 1 < _chromeApplyAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }
    }
  }
  try {
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    return true;
  } on Object catch (error) {
    if (kDebugMode) {
      devLog('窗口无边框兜底失败: ${error.runtimeType}');
    }
    return false;
  }
}

/// 页面级沉浸窗口状态控制器。
///
/// 租约只表达"页面正在占用无边框沉浸态"（进入即整窗无边框全屏，退出恢复
/// 原窗口摆放）；窗口全屏不设租约，统一由手动全屏（[setFullscreen] /
/// [toggleFullscreen]，F11 与各页全屏按钮）承担，避免双轨状态打架。
class WindowChromeController extends Notifier<WindowChromeState>
    with WindowListener {
  final Map<int, _WindowChromeRequest> _requests = {};
  int _nextRequestId = 0;
  int _desiredRevision = 0;
  bool _manualFullscreen = false;
  bool _appliedFullscreen = false;
  bool? _appliedChromeHidden;
  bool _resizableApplied = false;
  bool _immersivePlacementSaved = false;
  bool _placementSavePending = false;

  /// 桌面统一壳是自绘窗口：固定无边框，与全屏/沉浸互不干涉。
  /// 页面的沉浸租约仍是"临时占用"，这里表达的是"这台窗口本来就没有边框"。
  bool _frameless = false;
  Future<void> _applyQueue = Future<void>.value();

  @override
  WindowChromeState build() {
    if (isDesktopPlatform) {
      // 拖到屏幕边缘/顶部由系统直接最大化，不经过自绘中键；不听原生事件，
      // 中键图标会停在「最大化」，点下去却是还原。
      windowManager.addListener(this);
      ref.onDispose(() => windowManager.removeListener(this));
    }
    return const WindowChromeState();
  }

  @override
  void onWindowMaximize() => _syncMaximized(true);

  @override
  void onWindowUnmaximize() => _syncMaximized(false);

  void _syncMaximized(bool maximized) {
    if (!ref.mounted || state.isMaximized == maximized) {
      return;
    }
    // 只更新字形依据，不重跑 _setState：无边框/全屏的施加与最大化无关。
    state = state.copyWith(isMaximized: maximized);
  }

  WindowChromeLease acquire({
    required String owner,
    FutureOr<void> Function()? onExit,
  }) {
    final requestId = ++_nextRequestId;
    final shouldSavePlacement = _requests.isEmpty && !_manualFullscreen;
    _requests[requestId] = _WindowChromeRequest(owner: owner, onExit: onExit);
    if (shouldSavePlacement) {
      _placementSavePending = true;
    }
    _refreshState();
    return WindowChromeLease._(requestId, _releaseRequest);
  }

  WindowChromeLease acquireImmersive({
    required String owner,
    FutureOr<void> Function()? onExit,
  }) {
    return acquire(owner: owner, onExit: onExit);
  }

  Future<void> requestImmersive({
    required String owner,
    FutureOr<void> Function()? onExit,
  }) async {
    final existing = _requests.entries.where(
      (entry) => entry.value.owner == owner,
    );
    if (existing.isNotEmpty) {
      existing.last.value.onExit = onExit;
      return;
    }
    acquireImmersive(owner: owner, onExit: onExit);
  }

  Future<void> clearImmersive(String owner) async {
    final requestIds = _requests.entries
        .where((entry) => entry.value.owner == owner)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final requestId in requestIds) {
      _requests.remove(requestId);
    }
    _refreshState();
  }

  Future<void> exitImmersive() async {
    if (_requests.isEmpty) {
      _refreshState();
      return;
    }
    final entry = _requests.entries.last;
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
    // F11 以「窗口当前是否已处于全屏（手动意图或页面沉浸租约）」为基准
    // 切换：全屏中按一次即退出（先逐层释放沉浸租约，再撤销手动全屏），
    // 窗口态按一次进入全屏。避免旧行为"先退沉浸又强行保持手动全屏"
    // 造成的一次按键毫无反应或需两次才退出。
    final effectiveFullscreen = _manualFullscreen || _requests.isNotEmpty;
    if (!effectiveFullscreen) {
      await setFullscreen(true);
      return;
    }
    if (_requests.isNotEmpty) {
      await exitImmersive();
    }
    if (_manualFullscreen) {
      await setFullscreen(false);
    }
  }

  /// 固定无边框（桌面壳常驻）。与 [acquireImmersive] 的临时租约不同，
  /// 这里的隐藏不会顺带进入全屏。
  Future<void> setFrameless(bool enabled) async {
    if (!isDesktopPlatform || _frameless == enabled) {
      return;
    }
    _frameless = enabled;
    _setState(state.copyWith());
  }

  /// 从 Flutter 侧发起边缘缩放。
  ///
  /// 无边框窗口的客户区被 Flutter 子窗口铺满，系统拿不到边缘的
  /// WM_NCHITTEST（消息先被子窗口吃掉），所以缩放改由界面自己起头。
  Future<void> startResizing(WindowResizeEdge edge) async {
    if (!isDesktopPlatform) {
      return;
    }
    // 起手不能再问一次原生：`await windowManager.isMaximized()` 与随后的
    // `startResizing` 是两次 MethodChannel 往返（20~40ms），这期间鼠标已经
    // 离开窗口边缘，等原生 SC_SIZE 启动时窗口会顿挫跳一下。最大化状态本来
    // 就由 windowManager 的监听同步在内存里（中键字形也吃这份状态），直接读。
    //
    // 最大化/全屏时没有可缩放的边：命中带已被界面侧整体让位，这里再兜一次，
    // 避免通过其它入口误触发「拖边把窗口从最大化拖出来」。
    if (state.isMaximized || state.isFullscreen) {
      return;
    }
    await windowManager.startResizing(switch (edge) {
      WindowResizeEdge.topLeft => ResizeEdge.topLeft,
      WindowResizeEdge.top => ResizeEdge.top,
      WindowResizeEdge.topRight => ResizeEdge.topRight,
      WindowResizeEdge.right => ResizeEdge.right,
      WindowResizeEdge.bottomRight => ResizeEdge.bottomRight,
      WindowResizeEdge.bottom => ResizeEdge.bottom,
      WindowResizeEdge.bottomLeft => ResizeEdge.bottomLeft,
      WindowResizeEdge.left => ResizeEdge.left,
    });
  }

  /// 拖动窗口（自绘标题栏即拖拽区）。
  Future<void> startDragging() async {
    if (!isDesktopPlatform) {
      return;
    }
    await windowManager.startDragging();
  }

  /// 最大化/还原切换（自绘标题栏的中键与双击标题栏）。
  Future<void> toggleMaximize() async {
    if (!isDesktopPlatform) {
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      // Windows 直接依据已同步的内存状态单次派发 WM_SYSCOMMAND，避免
      // isMaximized + maximize/unmaximize 双次 MethodChannel 往返延迟。
      final targetMaximized = !state.isMaximized;
      try {
        await _windowFrameChannel.invokeMethod<void>(
          'windowAction',
          <String, dynamic>{'action': targetMaximized ? 'maximize' : 'restore'},
        );
        _syncMaximized(targetMaximized);
        return;
      } on Object catch (error) {
        if (kDebugMode) {
          devLog('Windows 原生最大化/还原通道失败，回退 window_manager: $error');
        }
      }
    }
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
      _syncMaximized(false);
      return;
    }
    await windowManager.maximize();
    _syncMaximized(true);
  }

  Future<void> minimize() async {
    if (!isDesktopPlatform) {
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      try {
        await _windowFrameChannel.invokeMethod<void>(
          'windowAction',
          const <String, dynamic>{'action': 'minimize'},
        );
        return;
      } on Object catch (error) {
        if (kDebugMode) {
          devLog('Windows 原生最小化通道失败，回退 window_manager: $error');
        }
      }
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
    final hidden =
        _frameless || next.immersiveOwner != null || next.isFullscreen;
    state = next.copyWith(chromeHidden: hidden);
    final target = state;
    final revision = ++_desiredRevision;
    _applyQueue = _applyQueue.then(
      (_) => _applyChrome(target, revision),
      onError: (Object error, StackTrace stackTrace) {
        if (kDebugMode) {
          devLog('Previous window chrome update failed: $error');
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
          devLog('System UI update failed: $error');
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
        devLog('Window chrome apply failed: $error');
      }
      return;
    }
    if (revision != _desiredRevision) {
      return;
    }
    // 无边框/全屏切换后客户区可能与 Flutter 视图短暂不一致（黑屏/黑边），
    // 统一做一次原生几何自愈；窗口态 chrome 已 ForceRedraw，无需 settle。
    if (target.isFullscreen || target.chromeHidden) {
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
        devLog('Window fullscreen update failed: $error');
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
        devLog('Window title bar update failed: $error');
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
        devLog('Window resizable update failed: $error');
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
        devLog('Window frame verify failed: $error');
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
        devLog('Window placement save failed: $error');
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
        devLog('Window placement restore failed: $error');
      }
    } finally {
      _immersivePlacementSaved = false;
    }
  }

  /// 等待已排队的窗口状态变更全部应用完成（含原生通道往返与几何自愈）。
  ///
  /// 原生吸附期间引擎重建渲染表面、不产帧：调用方据此把视觉过渡安排在
  /// 吸附落定之后，避免动画帧被吞掉。队列内部已消化错误，不会抛出。
  Future<void> get applied => _applyQueue;
}

class _WindowChromeRequest {
  _WindowChromeRequest({required this.owner, this.onExit});

  final String owner;
  FutureOr<void> Function()? onExit;
}
