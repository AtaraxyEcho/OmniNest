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

/// 黑场压暗时长（桌面端吸附前）；淡回内容使用 [_dipFadeInDuration]。
const _dipOutDuration = Duration(milliseconds: 160);
const _dipFadeInDuration = Duration(milliseconds: 450);

/// 黑场遮罩标识：测试据此断言压暗与原生吸附的先后关系。
@visibleForTesting
const slideshowDipOverlayKey = ValueKey<String>('slideshow-dip-overlay');

/// Fullscreen immersive slideshow (design: Photos Management UI Design).
///
/// Black full-bleed photos, dual-layer crossfade, segmented progress, collapsible
/// thumb strip, info panel, keyboard and fullscreen. Chrome auto-hides after
/// 3s idle; canvas tap toggles chrome. Native immersive snap starts only after
/// the route entrance transition settles, so the monitor snap's resize first
/// frame never relayouts the page stack below (Windows black-flash source).
class PhotoSlideshowPage extends ConsumerStatefulWidget {
  const PhotoSlideshowPage({
    required this.photos,
    required this.source,
    this.sourceKey,
    this.initialIndex = 0,
    super.key,
  });

  final List<PhotoItem> photos;
  final PhotoBrowseSource source;
  final String? sourceKey;
  final int initialIndex;

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

  /// 入场自绘扩缩：原生窗口切换为一步吸附，丝滑过渡由内容层缩放+淡入承担。
  late final AnimationController _entryController;
  late final Animation<double> _entryScale;
  late final Animation<double> _entryFade;

  /// 黑场控制器（桌面端）：压暗到全黑后才吸附原生窗口，交换链重建的
  /// 黑帧因此落入设计内的黑场；全屏首帧后再淡回内容。
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

  @override
  void initState() {
    super.initState();
    _photos = List.unmodifiable(widget.photos);
    _current =
        widget.photos.isEmpty
            ? 0
            : widget.initialIndex.clamp(0, _photos.length - 1);
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
      duration: const Duration(milliseconds: 320),
    )..addStatusListener(_onEntryStatus);
    final entryCurve = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    // 不从 opacity 0 淡入：原生窗口切到全屏时会露出纯黑窗口。
    // 仅做轻微 scale，保证切换过程中画面始终可见。
    _entryScale = Tween<double>(begin: 0.96, end: 1).animate(entryCurve);
    _entryFade = const AlwaysStoppedAnimation<double>(1);
    // 压暗快、淡回慢：吸附发生在黑场底部，返回时留足淡入观感。
    _dipController = AnimationController(
      vsync: this,
      duration: _dipOutDuration,
      reverseDuration: _dipFadeInDuration,
    );
    _dipOpacity = CurvedAnimation(
      parent: _dipController,
      curve: Curves.easeInOut,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_bootstrapSlideshow());
    });
  }

  /// 先画封面/加载态，等路由入场过渡完成后再进沉浸全屏，最后解码位图。
  ///
  /// 吸附必须等过渡完成：过渡期间下层页面仍在舞台上，中途切换原生窗口
  /// 几何会让新尺寸首帧叠加下层整树重排，Windows 上表现为约 1 秒黑屏卡顿。
  /// 过渡完成后下层已 offstage（不布局不绘制），吸附首帧只需布局本页。
  /// 桌面端吸附前先压暗到全黑（黑场）：原生交换链重建的黑帧量级由引擎
  /// 决定、应用层无法消除，落在设计内的黑场里即不可见。
  Future<void> _bootstrapSlideshow() async {
    // 进场即预热首图两档:取图/解码与路由过渡、原生全屏吸附并行。preview 档
    // 解码宽绑定显示器物理尺寸(见 SlideshowImageCache),预解码即终档,吸附
    // 完成时高清档大概率已在缓存中等待原位升级。
    unawaited(_prewarmInitialImage());
    if (!await _waitForRouteTransition()) {
      return;
    }
    if (!mounted) {
      return;
    }
    if (!await _dipToBlack()) {
      return;
    }
    if (!mounted) {
      return;
    }
    _windowChromeLease = ref
        .read(windowChromeControllerProvider.notifier)
        .acquireImmersive(owner: 'photos.slideshow');
    if (isDesktopPlatform) {
      // 原生吸附期间引擎重建渲染表面、不产帧：必须等吸附落定（含几何自愈与
      // DwmFlush 往返）再开始淡入，否则淡入的前半段被吞掉，黑场在观感上表现
      // 为"一瞬间直接消失"。上限 400ms 兜底：原生通道无回包时不能停在黑场。
      try {
        await ref
            .read(windowChromeControllerProvider.notifier)
            .applied
            .timeout(const Duration(milliseconds: 400), onTimeout: () {});
      } on Exception catch (error) {
        devLog('Window chrome apply wait failed: $error');
      }
      if (!mounted) {
        return;
      }
    }
    // 等新客户区首帧呈现后再放行淡入。
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    // 吸附落定后的首帧起：内容轻微扩缩 + 黑场反向淡回（见 _entryScale），
    // 二者同刻收尾，整体读作一次连续的"暗 → 吸附 → 亮"。
    _entryController.forward();
    unawaited(_dipController.reverse());
    await _loadInitialImage();
  }

  /// 桌面端吸附前压暗到全黑；非桌面端无原生窗口几何切换，不做黑场。
  ///
  /// 页面在压暗途中退出时等待链随 State 一并回收，返回 false 放弃吸附。
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
    await _imageCache.obtain(photo, ImageQuality.thumbnail, context);
    if (mounted) {
      await _imageCache.obtain(photo, ImageQuality.preview, context);
    }
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _goNext();
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
  Future<void> _loadInitialImage() async {
    if (!_hasImage(_photos[_current])) {
      setState(() {
        _phase = SlideshowPhase.ready;
      });
      _progressController.forward(from: 0);
      _preloadNeighbors();
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
      _progressController.forward(from: 0);
      _preloadNeighbors();
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
      setState(() {
        if (image != null) {
          _imageCache.retain(
            SlideshowImageCache.keyFor(
              _photos[_current].id,
              ImageQuality.thumbnail,
            ),
            image,
          );
          _currentFrame = SlideFrame(_photos[_current], image);
          _phase = SlideshowPhase.ready;
        } else {
          _phase = SlideshowPhase.failed;
        }
      });
      if (image != null) {
        _progressController.forward(from: 0);
        _preloadNeighbors();
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

  /// 首图加载失败后的重试入口。
  Future<void> _retryInitialLoad() async {
    if (_phase != SlideshowPhase.failed) return;
    setState(() => _phase = SlideshowPhase.loading);
    await _loadInitialImage();
  }

  /// 当前帧为缩略图档时，后台解码 preview 档并原位替换（渐进升级）。
  ///
  /// 解码期间可能已切到其他照片，回写前按照片 id 校验，避免旧图覆盖新帧；
  /// 位图已缓存或与当前帧同源时直接跳过。大图首次绘制的纹理上传较重，
  /// 替换动作等待入场扩缩动画结束后执行，不与原生吸附恢复期争抢光栅预算。
  Future<void> _upgradeCurrentImage() async {
    final photo = _currentPhoto;
    if (!_hasImage(photo)) return;
    final image = await _imageCache.obtain(
      photo,
      ImageQuality.preview,
      context,
    );
    if (!mounted || image == null) return;
    await _entrySettled.future;
    if (!mounted) return;
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

  /// 播放集合随来源类型实时扩展：库/收藏跟随分页控制器，影集/标签为全量查询。
  /// 地点/时间线为进入时锁定的子集，不做全库回退替换。
  void _ensurePlaylist() {
    switch (widget.source) {
      case PhotoBrowseSource.library:
        final live =
            ref.read(photoCenterControllerProvider).asData?.value.photos;
        if (live != null && live.length > _photos.length) _photos = live;
      case PhotoBrowseSource.favorites:
        final live =
            ref.read(photoCenterControllerProvider).asData?.value.favorites;
        if (live != null && live.length > _photos.length) _photos = live;
      case PhotoBrowseSource.album:
        final detail =
            ref.read(photoAlbumDetailProvider(widget.sourceKey!)).asData?.value;
        final photos = detail?.photos;
        if (photos != null && photos.length > _photos.length) _photos = photos;
      case PhotoBrowseSource.tag:
        final tagged =
            ref.read(photosByTagProvider(widget.sourceKey!)).asData?.value;
        if (tagged != null && tagged.length > _photos.length) _photos = tagged;
      case PhotoBrowseSource.locations:
      case PhotoBrowseSource.timeline:
        // 地点=进入时锁定的该地点照片；时间线范围播放由批次 B 的
        // by-period 端点接入。两者均保留传入子集。
        break;
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
      if (_isPlaying) {
        _progressController.forward(from: 0);
      }
      unawaited(_transitionController.forward(from: 0));
      return;
    }
    setState(() => _awaitingTarget = true);

    try {
      // 列表种子（如首页最近照片）常只有 coverUrl、没有 sourceUrl：
      // preview 档会静默失败导致无法切换，必须回退到 thumbnail 档。
      final targetPhoto = _photos[target];
      final hasSource = targetPhoto.sourceUrl?.isNotEmpty == true;
      var quality = hasSource ? ImageQuality.preview : ImageQuality.thumbnail;
      var image = await _imageCache.obtain(targetPhoto, quality, context);
      if (!mounted) return;
      if (image == null && hasSource && _hasImage(targetPhoto)) {
        quality = ImageQuality.thumbnail;
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
        if (_isPlaying) {
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

      if (_isPlaying) {
        _progressController.forward(from: 0);
      }
      unawaited(_transitionController.forward(from: 0));
    } catch (error, stackTrace) {
      devLog('Slideshow transition failed: $error');
      devLogStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() => _awaitingTarget = false);
      if (_isPlaying) {
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
        _progressController.forward(from: 0);
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
      final savedPath = await ref
          .read(photoCenterControllerProvider.notifier)
          .savePhotoFileToDisk(
            url: sourceUrl,
            sizeBytes: photo.fileSize,
            suggestedName: photo.downloadFileName,
          );
      if (!mounted || savedPath == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).photosDownloadSaved(savedPath),
          ),
        ),
      );
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
                // 黑场遮罩（桌面端）：吸附前压暗到全黑，使原生交换链重建的
                // 黑帧落入设计内的黑场；全屏首帧后反向淡回。非桌面端无原生
                // 窗口几何切换，不引入多余黑场。
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

  /// 舞台内容（照片层、控件与面板）：由 build 挂入场扩缩与黑场之下。
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
