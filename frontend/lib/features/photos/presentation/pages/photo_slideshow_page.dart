import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/utils/fullscreen_helper.dart' as fs;
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/window/window_chrome_controller.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/platform/photo_batch_web_download.dart';
import 'package:omninest/features/photos/presentation/pages/photo_slideshow_image_cache.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_info_panel.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_panel_host.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_share_panel.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_slideshow_chrome.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_slideshow_overlays.dart';
import 'package:omninest/core/log/dev_log.dart';

/// 幻灯片页面阶段：首图解码中 / 可播放 / 首图加载失败。
enum SlideshowPhase { loading, ready, failed }

const _slideshowInterval = Duration(seconds: 5);
const _transitionDuration = Duration(milliseconds: 450);
const _idleHideDuration = Duration(seconds: 3);
const _transitionCurve = Curves.easeOutCubic;

/// 入场扩缩时长：略长于压暗淡入的前半段，避免缩放突然弹出。
const _entryDuration = Duration(milliseconds: 320);

/// 压暗淡入 / 淡回时长。
///
/// 淡入要慢：此前 80ms 压暗接近一帧完成，叠加原生吸附丢帧会看成闪烁。
/// 淡回同样放缓，让画面从暗到亮连续，而不是“瞬间亮起”。
const _dipOutDuration = Duration(milliseconds: 280);
const _dipFadeInDuration = Duration(milliseconds: 420);

/// 吸附落定等待上限（压暗底部）。
///
/// 只等交换链重建所需的短窗，不再 `await applied` 2 秒。超时也继续淡回，
/// 黑场时长可控，不会把用户钉在纯黑上。
const _dipChromeSettle = Duration(milliseconds: 450);

/// preview 高清档升级前，等待原生吸附落定的上限。
///
/// 吸附与首图上屏并行；大图纹理上传很重，等吸附落定再升级，避免与
/// 交换链重建抢光栅预算。超时兜底，不阻塞用户已看到的画面。
const _previewUpgradeChromeSettle = Duration(milliseconds: 400);

/// 判定为卡顿/停帧的单帧间隔；超过则重置自动播放计时。
const _frameGapFreezeThreshold = Duration(milliseconds: 800);

/// 黑场遮罩标识：测试据此断言压暗为多帧渐变且会退回透明。
@visibleForTesting
const slideshowDipOverlayKey = ValueKey<String>('slideshow-dip-overlay');

/// Fullscreen immersive slideshow (design: Photos Management UI Design).
///
/// Black full-bleed photos, dual-layer crossfade, segmented progress, collapsible
/// thumb strip, info panel, keyboard and fullscreen. Chrome auto-hides after
/// 3s idle; canvas tap toggles chrome. Entry uses a slow soft dim: content is
/// already painted underneath, then dimmed over ~280ms, the native snap runs
/// under that dim, and the frame eases back in over ~420ms. No multi-second
/// black hold, no one-frame blink.
class PhotoSlideshowPage extends ConsumerStatefulWidget {
  const PhotoSlideshowPage({
    required this.photos,
    required this.source,
    this.sourceKey,
    this.initialIndex = 0,
    this.initialPhotoId,
    super.key,
  });

  final List<PhotoItem> photos;
  final PhotoBrowseSource source;
  final String? sourceKey;
  final int initialIndex;

  /// 起播照片 id：列表扩展/重排时按 id 锚定，避免下标错位播错张。
  final String? initialPhotoId;

  @override
  ConsumerState<PhotoSlideshowPage> createState() => _PhotoSlideshowPageState();
}

class _PhotoSlideshowPageState extends ConsumerState<PhotoSlideshowPage>
    with TickerProviderStateMixin {
  late List<PhotoItem> _photos;
  late int _current;
  bool _isPlaying = true;
  bool _controlsVisible = true;
  bool _thumbnailsVisible = true;
  bool _showInfo = false;
  bool _showShare = false;
  Timer? _idleTimer;
  late AnimationController _progressController;
  late AnimationController _transitionController;
  late Animation<double> _transitionFade;
  WindowChromeLease? _windowChromeLease;

  /// 入场扩缩动画结束信号：preview 大图原位升级等待它，避免大图首绘的
  /// 纹理上传与原生吸附恢复期争抢光栅预算；页面销毁时兜底置位以释放等待方。
  final Completer<void> _entrySettled = Completer<void>();

  /// 画面开始对用户可见（入场扩缩启动）。
  ///
  /// 自动播放计时从此刻起算：此前启动的 forward 会在停帧期间按墙钟补算，
  /// 导致用户看到首帧时已经跳到下一张。
  final Completer<void> _presentationVisible = Completer<void>();

  /// 起播锚点照片 id（优先于下标）。
  String? _anchorPhotoId;

  /// 上一帧时间戳：用于检测启动期停帧并重置自动播放计时。
  DateTime? _lastFrameAt;

  /// 入场自绘扩缩：原生窗口一步吸附，丝滑过渡由内容层缩放 + 压暗淡回承担。
  late final AnimationController _entryController;
  late final Animation<double> _entryScale;
  late final Animation<double> _entryFade;

  /// 压暗遮罩：淡入盖住吸附窗口，吸附落定后缓慢淡回。
  late final AnimationController _dipController;
  late final Animation<double> _dipOpacity;

  /// 解码位图缓存：位图本体归 ImageCache 所有（live 保活），本页持窗口引用。
  late final SlideshowImageCache _imageCache = SlideshowImageCache();

  /// 当前显示帧（照片 + 解码位图）；就绪门控保证有图照片动画开始时 image 非空。
  SlideFrame? _currentFrame;

  /// 交叉过渡期间的离场帧；动画完成置 null。
  SlideFrame? _leavingFrame;

  /// TRANSITIONING 阶段：交叉动画进行中。
  bool _transitioning = false;

  /// 切换等待中：目标位图解码期间保持当前帧并忽略重复触发。
  bool _awaitingTarget = false;

  /// 等待期间的最终导航目标：当前加载完成后链式推进（快速连点不丢操作）。
  int? _pendingTarget;

  /// 页面阶段：loading（首图解码中）/ ready（可播放）/ failed（首图加载失败）。
  SlideshowPhase _phase = SlideshowPhase.loading;

  /// 首图加载只启动一次（预热链与 bootstrap 可能同时触发）。
  bool _initialLoadStarted = false;

  @override
  void initState() {
    super.initState();
    _photos = List.unmodifiable(widget.photos);
    _current =
        widget.photos.isEmpty
            ? 0
            : widget.initialIndex.clamp(0, _photos.length - 1);
    _anchorPhotoId =
        widget.initialPhotoId ??
        (widget.photos.isEmpty ? null : widget.photos[_current].id);
    // 按 id 锚定起播张，防止传入下标与后续列表扩展错位。
    _resolveAnchorIndex();
    // 进度条经 ValueListenableBuilder 局部刷新，避免 30ms tick 触发整页重建。
    _progressController = AnimationController(
      vsync: this,
      duration: _slideshowInterval,
    )..addStatusListener(_onProgressStatus);
    // 交叉过渡控制器常驻：动画只更新层属性，层位图引用跨切换稳定；
    // 完成清理由过渡自身的 completed 状态驱动，与动画时序严格同步，不依赖 Timer。
    _transitionController = AnimationController(
      vsync: this,
      duration: _transitionDuration,
    )..addStatusListener(_onTransitionStatus);
    _transitionFade = CurvedAnimation(
      parent: _transitionController,
      curve: _transitionCurve,
    );
    _entryController = AnimationController(
      vsync: this,
      duration: _entryDuration,
    )..addStatusListener(_onEntryStatus);
    final entryCurve = CurvedAnimation(
      parent: _entryController,
      // 对称缓入缓出：缩放与压暗淡回同一节奏，避免“弹一下”的突兀感。
      curve: Curves.easeInOutCubic,
    );
    // 不从 opacity 0 淡入：淡入交给压暗层，内容本身始终可绘制。
    _entryScale = Tween<double>(begin: 0.985, end: 1).animate(entryCurve);
    _entryFade = const AlwaysStoppedAnimation<double>(1);
    // 压暗/淡回都用长时长 + easeInOut，保证多帧渐变，消除闪烁。
    _dipController = AnimationController(
      vsync: this,
      duration: _dipOutDuration,
      reverseDuration: _dipFadeInDuration,
    );
    _dipOpacity = CurvedAnimation(
      parent: _dipController,
      curve: Curves.easeInOut,
      reverseCurve: Curves.easeInOutCubic,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_bootstrapSlideshow());
    });
  }

  /// 内容先画、再软压暗、吸附、缓慢亮回。
  ///
  /// 淡入必须多帧完成：过快的压暗会在吸附丢帧时看成闪烁。黑场只覆盖
  /// 吸附短窗（[_dipChromeSettle]），不再 `await applied` 数秒。
  Future<void> _bootstrapSlideshow() async {
    // 进场即预热首图两档并尝试上屏：取图/解码与路由过渡并行。
    unawaited(_prewarmInitialImage());
    unawaited(_loadInitialImage());
    if (!await _waitForRouteTransition()) {
      return;
    }
    if (!mounted) {
      return;
    }
    // 桌面：在已有内容上缓慢压暗，为原生吸附铺一层视觉缓冲。
    if (isDesktopPlatform) {
      await _dipToBlack();
      if (!mounted) {
        return;
      }
    }
    // 沉浸租约与压暗底部重叠：吸附黑帧落入遮罩之下。
    _windowChromeLease = ref
        .read(windowChromeControllerProvider.notifier)
        .acquireImmersive(owner: 'photos.slideshow');
    if (isDesktopPlatform) {
      try {
        await ref
            .read(windowChromeControllerProvider.notifier)
            .applied
            .timeout(_dipChromeSettle, onTimeout: () {});
      } on Exception catch (error) {
        devLog('Window chrome apply wait failed: $error');
      }
      if (!mounted) {
        return;
      }
    }
    // 呈现与淡回、扩缩同刻启动：用户看到的是连续的“暗 → 亮 + 轻微推近”。
    if (!_presentationVisible.isCompleted) {
      _presentationVisible.complete();
    }
    _entryController.forward();
    unawaited(_dipController.reverse());
  }

  /// 桌面端软压暗到全黑；非桌面端无原生几何切换，不做遮罩。
  Future<bool> _dipToBlack() async {
    if (!isDesktopPlatform) {
      return true;
    }
    await _dipController.forward(from: 0);
    return mounted;
  }

  /// 等待路由入场过渡完成（completed）。
  ///
  /// 过渡期内页面被退出（动画走向 dismissed）时返回 false，调用方放弃
  /// 沉浸租约申请；页面本身随即销毁，不会出现租约悬挂。
  Future<bool> _waitForRouteTransition() {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) {
      return Future<bool>.value(true);
    }
    if (animation.isDismissed) {
      return Future<bool>.value(false);
    }
    final completer = Completer<bool>();
    late final AnimationStatusListener listener;
    listener = (AnimationStatus status) {
      if (completer.isCompleted) {
        return;
      }
      if (status == AnimationStatus.completed) {
        completer.complete(true);
      } else if (status == AnimationStatus.dismissed) {
        completer.complete(false);
      }
    };
    animation.addStatusListener(listener);
    return completer.future.whenComplete(() {
      animation.removeStatusListener(listener);
    });
  }

  Future<void> _prewarmInitialImage() async {
    if (!mounted) {
      return;
    }
    final photo = _photos[_current];
    if (!_hasImage(photo)) {
      return;
    }
    // 只预热缩略图（cover@400，毫秒级）。preview 档解码宽绑定显示器物理
    // 像素、首绘纹理上传很重，必须等入场/吸附落定后再做（见
    // _upgradeCurrentImage），否则启动阶段会卡死 UI 数秒。
    await _imageCache.obtain(photo, ImageQuality.thumbnail, context);
  }

  void _onProgressStatus(AnimationStatus status) {
    // 入场/吸附未完成时不自动切图：启动期帧停顿会让 ticker 按墙钟一次跳完，
    // 用户刚看到画面就已经是下一张。展示开始后由 [_startProgressWhenPresented]
    // 重新计时。
    if (status == AnimationStatus.completed &&
        _presentationVisible.isCompleted) {
      _goNext();
    }
  }

  /// 入场扩缩动画结束即置位 [_entrySettled]，放行 preview 大图原位升级。
  void _onEntryStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_entrySettled.isCompleted) {
      _entrySettled.complete();
    }
  }

  /// 过渡动画到达终点（completed）时同步清理离场层并恢复静止态。
  void _onTransitionStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _transitioning) {
      _onTransitionCompleted();
    }
  }

  /// 交叉动画完成：清除离场层、背景跟进新图、窗口整理并预热邻居、
  /// 消化等待期间记录的最终导航目标。
  void _onTransitionCompleted() {
    _transitionController.reset();

    setState(() {
      _leavingFrame = null;
      _transitioning = false;
    });
    _imageCache.updateWindow(_photos, _current);
    _preloadNeighbors();
    final pending = _pendingTarget;
    _pendingTarget = null;
    if (pending != null && pending != _current) {
      unawaited(_goTo(pending));
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _progressController.dispose();
    _transitionController.dispose();
    // 入场结束信号兜底置位，释放仍在等待 preview 升级的异步链。
    if (!_entrySettled.isCompleted) {
      _entrySettled.complete();
    }
    if (!_presentationVisible.isCompleted) {
      _presentationVisible.complete();
    }
    _entryController.dispose();
    _dipController.dispose();
    _windowChromeLease?.release();
    // 位图本体归 ImageCache 所有（live 保活），页面销毁不 dispose；
    // 窗口引用随 State 释放，后台完成的解码因 _disposed 守卫不再写回。
    _imageCache.dispose();
    super.dispose();
  }

  PhotoItem get _currentPhoto => _photos[_current];

  /// 首图加载：成功进入 ready；失败进入 failed（UI 提供重试）；无图照片按占位层就绪。
  ///
  /// 与原生吸附解耦：缩略图就绪即上屏，避免用户在黑场/吸附链上干等。
  /// 进度条在入场扩缩结束后才启动，保证「可见后再计时」。
  Future<void> _loadInitialImage() async {
    if (_initialLoadStarted && _phase != SlideshowPhase.failed) {
      return;
    }
    _initialLoadStarted = true;
    if (!_hasImage(_photos[_current])) {
      setState(() {
        _phase = SlideshowPhase.ready;
      });
      unawaited(_startProgressWhenPresented());
      return;
    }
    final photo = _photos[_current];
    final peeked = _imageCache.peek(
      SlideshowImageCache.keyFor(photo.id, ImageQuality.thumbnail),
    );
    if (peeked != null) {
      setState(() {
        _imageCache.retain(
          SlideshowImageCache.keyFor(photo.id, ImageQuality.thumbnail),
          peeked,
        );
        _currentFrame = SlideFrame(photo, peeked);
        _phase = SlideshowPhase.ready;
      });
      unawaited(_startProgressWhenPresented());
      unawaited(_upgradeCurrentImage());
      return;
    }
    try {
      final image = await _imageCache.obtain(
        photo,
        ImageQuality.thumbnail,
        context,
      );
      if (!mounted) return;
      // 以发起加载时的 photo 为准，避免 await 期间列表扩展/重锚导致写错帧。
      setState(() {
        if (image != null) {
          _imageCache.retain(
            SlideshowImageCache.keyFor(photo.id, ImageQuality.thumbnail),
            image,
          );
          _currentFrame = SlideFrame(photo, image);
          _phase = SlideshowPhase.ready;
        } else {
          _phase = SlideshowPhase.failed;
        }
      });
      if (image != null) {
        unawaited(_startProgressWhenPresented());
        // 首图先以缩略图档立即显示，preview 高清档后台解码完成后原位替换。
        unawaited(_upgradeCurrentImage());
      }
    } catch (error, stackTrace) {
      devLog('Initial slideshow image failed: $error');
      devLogStack(stackTrace: stackTrace);

      if (!mounted) return;
      setState(() => _phase = SlideshowPhase.failed);
    }
  }

  /// 画面开始可见后再启动自动播放计时。
  ///
  /// 启动期原生吸附/大图解码会停帧，AnimationController 按墙钟补算，
  /// 若在不可见阶段就 forward，用户看到首帧时进度可能已走完并跳到下一张。
  Future<void> _startProgressWhenPresented() async {
    await _presentationVisible.future;
    if (!mounted || _phase != SlideshowPhase.ready) {
      return;
    }
    if (!_isPlaying) {
      return;
    }
    _progressController.forward(from: 0);
    // 入场扩缩落定后再预热邻居，避免与首图/preview 解码抢光栅预算。
    unawaited(() async {
      await _entrySettled.future;
      if (mounted) {
        _preloadNeighbors();
      }
    }());
  }

  /// 首图加载失败后的重试入口。
  Future<void> _retryInitialLoad() async {
    if (_phase != SlideshowPhase.failed) return;
    setState(() => _phase = SlideshowPhase.loading);
    _initialLoadStarted = false;
    await _loadInitialImage();
  }

  /// 当前帧为缩略图档时，后台解码 preview 档并原位替换（渐进升级）。
  ///
  /// 必须等入场扩缩落定后再启动 preview 解码：该档解码宽绑定显示器物理
  /// 像素且首绘纹理上传很重，放在启动路径上会把 UI 冻住数秒。
  /// 解码期间可能已切到其他照片，回写前按照片 id 校验，避免旧图覆盖新帧。
  Future<void> _upgradeCurrentImage() async {
    await _entrySettled.future;
    if (!mounted) return;
    // 与原生吸附错峰：大图纹理上传等交换链重建落定后再做，避免进场后
    // 数秒光栅卡顿。超时兜底，不把升级无限期挂起。
    if (isDesktopPlatform) {
      try {
        await ref
            .read(windowChromeControllerProvider.notifier)
            .applied
            .timeout(_previewUpgradeChromeSettle, onTimeout: () {});
      } on Exception catch (error) {
        devLog('Window chrome settle wait failed: $error');
      }
    }
    if (!mounted) return;
    final photo = _currentPhoto;
    if (!_hasImage(photo)) return;
    final image = await _imageCache.obtain(
      photo,
      ImageQuality.preview,
      context,
    );
    if (!mounted || image == null) return;
    final frame = _currentFrame;
    if (frame == null || frame.photo.id != photo.id) return;
    if (identical(frame.image, image)) return;
    _imageCache.retain(
      SlideshowImageCache.keyFor(photo.id, ImageQuality.preview),
      image,
    );
    if (!mounted || _currentFrame?.photo.id != photo.id) return;
    setState(() {
      if (_currentFrame?.photo.id == photo.id) {
        _currentFrame = SlideFrame(photo, image);
      }
    });
  }

  /// 当前缓存窗口由 SlideshowImageCache 内部管理（current ± radius）。

  /// 将 [_current] 对齐到 [_anchorPhotoId]；找不到时保持原下标。
  void _resolveAnchorIndex() {
    final anchorId = _anchorPhotoId;
    if (anchorId == null || _photos.isEmpty) {
      return;
    }
    final index = _photos.indexWhere((p) => p.id == anchorId);
    if (index >= 0) {
      _current = index;
    }
  }

  /// 播放集合随来源类型实时扩展：库/收藏跟随分页控制器，影集/标签为全量查询。
  /// 地点/时间线为进入时锁定的子集，不做全库回退替换。
  ///
  /// 扩展列表时必须按照片 id 重锚 [_current]：传入子集的下标与全量列表
  /// 不是对齐关系，直接沿用会把起播张换成另一张（常表现为「一进来就第二张」）。
  /// 锚点不在新列表时不扩展，避免起播张被顶掉。
  void _ensurePlaylist() {
    final List<PhotoItem>? live = switch (widget.source) {
      PhotoBrowseSource.library =>
        ref.read(photoCenterControllerProvider).asData?.value.photos,
      PhotoBrowseSource.favorites =>
        ref.read(photoCenterControllerProvider).asData?.value.favorites,
      PhotoBrowseSource.album =>
        ref
            .read(photoAlbumDetailProvider(widget.sourceKey!))
            .asData
            ?.value
            .photos,
      PhotoBrowseSource.tag =>
        ref.read(photosByTagProvider(widget.sourceKey!)).asData?.value,
      PhotoBrowseSource.locations || PhotoBrowseSource.timeline => null,
    };
    if (live == null || live.length <= _photos.length) {
      return;
    }
    final anchorId = _anchorPhotoId;
    if (anchorId != null && !live.any((p) => p.id == anchorId)) {
      return;
    }
    _photos = live;
    _resolveAnchorIndex();
  }

  /// 单帧间隔过大（原生吸附/大图解码停帧）时重置自动播放计时。
  ///
  /// AnimationController 按墙钟补算会把停帧算进播放时长；重置后用户
  /// 至少能看到当前张完整的展示间隔，不会「一露脸就下一张」。
  void _noteFrameGap() {
    final now = DateTime.now();
    final previous = _lastFrameAt;
    _lastFrameAt = now;
    if (previous == null || !_presentationVisible.isCompleted) {
      return;
    }
    if (now.difference(previous) < _frameGapFreezeThreshold) {
      return;
    }
    if (_isPlaying && _phase == SlideshowPhase.ready && !_transitioning) {
      _progressController.forward(from: 0);
    }
  }

  bool _hasImage(PhotoItem item) =>
      (item.sourceUrl ?? item.coverUrl)?.isNotEmpty == true;

  /// 预加载优先级：下一张 > 上一张（窗口半径内的后台预热）。
  void _preloadNeighbors() {
    for (final offset in const [1, -1]) {
      final index =
          ((_current + offset) % _photos.length + _photos.length) %
          _photos.length;
      if (!_hasImage(_photos[index])) continue;
      unawaited(() async {
        final image = await _imageCache.obtain(
          _photos[index],
          ImageQuality.thumbnail,
          context,
        );
        if (image != null) {
          _imageCache.retain(
            SlideshowImageCache.keyFor(
              _photos[index].id,
              ImageQuality.thumbnail,
            ),
            image,
          );
        }
      }());
    }
  }

  Future<void> _goTo(int index) async {
    if (_transitioning ||
        _awaitingTarget ||
        _phase != SlideshowPhase.ready ||
        _photos.isEmpty) {
      return;
    }
    final target = ((index % _photos.length) + _photos.length) % _photos.length;
    if (target == _current) return;
    // 切换等待期间冻结进度条：解码耗时超过剩余间隔时，
    // 进度完成回调不会再触发新一轮导航造成连续跳转。
    _progressController.stop();
    // 无图照片（元数据条目）：无需位图，直接切换到占位层。
    if (!_hasImage(_photos[target])) {
      setState(() {
        _current = target;
        _transitioning = true;
      });
      if (_isPlaying && _presentationVisible.isCompleted) {
        _progressController.forward(from: 0);
      }
      unawaited(_transitionController.forward(from: 0));
      return;
    }
    setState(() => _awaitingTarget = true);

    try {
      // 先取缩略图秒显，preview 高清档等当前帧升级链路处理；
      // 切换路径若直接等 preview，大图解码会把切换拖成数秒卡顿。
      final targetPhoto = _photos[target];
      var quality = ImageQuality.thumbnail;
      var image = await _imageCache.obtain(targetPhoto, quality, context);
      if (!mounted) return;
      if (image == null && _hasImage(targetPhoto)) {
        quality = ImageQuality.preview;
        image = await _imageCache.obtain(targetPhoto, quality, context);
      }

      if (!mounted) return;

      if (image == null) {
        // 加载失败（网络错误等）：保持当前图，允许用户重试；
        // 自动播放中重启进度计时，避免单张失败打断整个循环。
        setState(() {
          _awaitingTarget = false;
          _pendingTarget = null;
        });
        if (_isPlaying && _presentationVisible.isCompleted) {
          _progressController.forward(from: 0);
        }
        return;
      }

      // TRANSITIONING：位图已就绪，动画只做合成，不触碰图片来源。
      _imageCache.retain(
        SlideshowImageCache.keyFor(targetPhoto.id, quality),
        image,
      );
      setState(() {
        // 保存旧帧用于离场动画；更新当前显示帧。
        _leavingFrame = _currentFrame;
        _currentFrame = SlideFrame(_photos[target], image);

        _current = target;
        _awaitingTarget = false;
        _transitioning = true;
      });

      if (_isPlaying && _presentationVisible.isCompleted) {
        _progressController.forward(from: 0);
      }
      unawaited(_transitionController.forward(from: 0));
      if (quality == ImageQuality.thumbnail) {
        unawaited(_upgradeCurrentImage());
      }
    } catch (error, stackTrace) {
      devLog('Slideshow transition failed: $error');
      devLogStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() => _awaitingTarget = false);
      if (_isPlaying && _presentationVisible.isCompleted) {
        _progressController.forward(from: 0);
      }
    }
  }

  void _goNext() => unawaited(_goTo(_current + 1));

  void _goPrev() => unawaited(_goTo(_current - 1));

  /// 横向滑动切换：负速度为左滑（下一张），正速度为右滑（上一张）。
  void _onHorizontalDragEnd(DragEndDetails details) {
    _resetIdle();
    if (_photos.length < 2) return;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 280) return;
    if (velocity < 0) {
      _goNext();
    } else {
      _goPrev();
    }
  }

  void _togglePlay() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        if (_presentationVisible.isCompleted) {
          _progressController.forward(from: 0);
        }
      } else {
        _progressController.reset();
        _idleTimer?.cancel();
      }
      _controlsVisible = true;
    });
    if (_isPlaying) {
      _scheduleIdleHide();
    }
  }

  void _resetIdle() {
    if (!mounted) return;
    // MouseRegion.onHover fires on every pointer move (Web/desktop). Only
    // rebuild when chrome was hidden; always setState would repaint the
    // whole page and stall the segmented progress bar.
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _scheduleIdleHide();
  }

  /// Toggle chrome on canvas tap: hide when shown, show + resume idle timer when hidden.
  ///
  /// Allowed while paused so the user can stay immersive; tap again to restore.
  void _toggleControls() {
    if (!mounted) return;
    _idleTimer?.cancel();
    if (_controlsVisible) {
      setState(() => _controlsVisible = false);
      return;
    }
    _resetIdle();
  }

  void _scheduleIdleHide() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleHideDuration, () {
      if (!mounted) return;
      if (_isPlaying) setState(() => _controlsVisible = false);
    });
  }

  void _toggleFullscreen() {
    if (kIsWeb) {
      fs.toggleFullscreen();
      return;
    }
    ref.read(windowChromeControllerProvider.notifier).toggleFullscreen();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    _resetIdle();
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.space) {
      _goNext();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _goPrev();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyP) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyI) {
      setState(() {
        _showInfo = !_showInfo;
        if (_showInfo) _showShare = false;
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_showInfo || _showShare) {
        setState(() {
          _showInfo = false;
          _showShare = false;
        });
        return KeyEventResult.handled;
      }
      // 面板均未展开时 Esc 退出幻灯片，与顶栏关闭按钮同路径。
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _toggleFavorite(PhotoItem photo) async {
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .toggleFavorite(photo.id, currentFavorite: photo.favorite);
      if (!mounted) return;
      ref.invalidate(photoDetailProvider(photo.id));
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).photosOperationFailed),
        ),
      );
    }
  }

  Future<void> _downloadPhoto(PhotoItem photo) async {
    final sourceUrl = photo.sourceUrl;
    if (sourceUrl == null || sourceUrl.isEmpty) return;
    try {
      if (kIsWeb) {
        unawaited(
          downloadPhotoBatchInBrowser(
            url: sourceUrl,
            fileName: photo.downloadFileName,
          ),
        );
        return;
      }
      final exportResult = await ref
          .read(photoCenterControllerProvider.notifier)
          .savePhotoFileToDisk(
            url: sourceUrl,
            sizeBytes: photo.fileSize,
            suggestedName: photo.downloadFileName,
          );
      if (!mounted || exportResult is PhotoExportCancelled) return;
      final l10n = AppLocalizations.of(context);
      final message = switch (exportResult) {
        PhotoExportSaved(:final path) => l10n.photosDownloadSaved(path),
        PhotoExportShared() => l10n.photosExportShared,
        PhotoExportCancelled() => null,
      };
      if (message != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).photosDownloadFailed),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _noteFrameGap();
    _ensurePlaylist();
    final photo = _currentPhoto;
    final showControls = _controlsVisible;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: MouseRegion(
          cursor:
              _controlsVisible ? MouseCursor.defer : SystemMouseCursors.none,
          onHover: (_) => _resetIdle(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            child: Stack(
              fit: StackFit.expand,
              children: [
                FadeTransition(
                  opacity: _entryFade,
                  child: ScaleTransition(
                    scale: _entryScale,
                    child: _buildStage(context, photo, showControls),
                  ),
                ),
                // 软压暗遮罩（桌面端）：缓慢淡入盖住吸附，再缓慢淡回。
                // 非桌面端无原生窗口几何切换，不引入多余黑场。
                if (isDesktopPlatform)
                  IgnorePointer(
                    child: FadeTransition(
                      key: slideshowDipOverlayKey,
                      opacity: _dipOpacity,
                      child: const ColoredBox(color: Colors.black),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 舞台内容（照片层、控件与面板）：由 build 挂入场扩缩之下。
  Widget _buildStage(BuildContext context, PhotoItem photo, bool showControls) {
    return Stack(
      fit: StackFit.expand,
      children: [
        switch (_phase) {
          SlideshowPhase.loading => SlideshowLoadingStage(photo: photo),
          SlideshowPhase.failed => SlideshowErrorRetry(
            onRetry: () => unawaited(_retryInitialLoad()),
          ),
          SlideshowPhase.ready => Stack(
            fit: StackFit.expand,
            children: [
              SlideshowBackdropLayers(
                transition: _transitionFade,
                transitioning: _transitioning,
                leavingFrame: _leavingFrame,
                enteringFrame: _currentFrame,
              ),
              SlideshowSlideLayers(
                transition: _transitionFade,
                transitioning: _transitioning,
                leavingFrame: _leavingFrame,
                enteringFrame: _currentFrame,
              ),
            ],
          ),
        },
        SlideshowGradients(visible: showControls),
        PhotoSlideshowTopBar(
          photo: photo,
          current: _current,
          total: _photos.length,
          visible: showControls,
          showInfo: _showInfo,
          showShare: _showShare,
          onClose: () => Navigator.of(context).maybePop(),
          onToggleFavorite: () => _toggleFavorite(photo),
          onToggleShare:
              () => setState(() {
                _showShare = !_showShare;
                if (_showShare) _showInfo = false;
              }),
          onDownload: () => unawaited(_downloadPhoto(photo)),
          onToggleInfo: () => setState(() => _showInfo = !_showInfo),
          onFullscreen: _toggleFullscreen,
        ),
        if (_photos.length > 1) ...[
          SlideshowArrow(right: false, visible: showControls, onTap: _goPrev),
          SlideshowArrow(right: true, visible: showControls, onTap: _goNext),
        ],
        SlideshowBottomArea(
          photo: photo,
          visible: showControls,
          isPlaying: _isPlaying,
          thumbnailsVisible: _thumbnailsVisible,
          onTogglePlay: _togglePlay,
          onToggleThumbnails:
              () => setState(() => _thumbnailsVisible = !_thumbnailsVisible),
          segments: SlideshowSegments(
            count: _photos.length,
            current: _current,
            isPlaying: _isPlaying,
            progress: _progressController,
            onTap: (index) => unawaited(_goTo(index)),
          ),
          thumbnailStrip: SlideshowThumbnailStrip(
            photos: _photos,
            current: _current,
            onTap: (index) => unawaited(_goTo(index)),
          ),
        ),
        // 面板 scrim 在侧栏之下（zIndex 语义），点击空白处同时收起。
        if (_showInfo || _showShare)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap:
                  () => setState(() {
                    _showInfo = false;
                    _showShare = false;
                  }),
            ),
          ),
        _buildInfoPanel(context, photo),
        PhotoSharePanel(
          visible: _showShare,
          photo: photo,
          onDone:
              () => setState(() {
                _showShare = false;
              }),
        ),
      ],
    );
  }

  // ─── Info 面板 ───

  Widget _buildInfoPanel(BuildContext context, PhotoItem photo) {
    return PhotoPanelHost(
      visible: _showInfo,
      onClose: () => setState(() => _showInfo = false),
      child: PhotoInfoPanel(
        photo: photo,
        onShare:
            () => setState(() {
              _showInfo = false;
              _showShare = true;
            }),
      ),
    );
  }
}
