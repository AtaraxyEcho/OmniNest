import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:omninest/features/video/presentation/widgets/movie_common_widgets.dart';

/// 关系图谱之外共用的 Hero 轮播条目。
class MediaHeroEntry {
  const MediaHeroEntry({
    required this.id,
    this.backdropUrl,
    this.posterUrl,
    required this.overlay,
  });

  /// 条目 ID，点击时通过 [MediaHeroCarousel.onOpen] 回传。
  final String id;
  final String? backdropUrl;
  final String? posterUrl;

  /// 覆盖层内容（标题、标签、操作按钮等），由各模块自行构建。
  final Widget overlay;
}

/// 电影与剧集共用的 3D Hero 轮播。
///
/// 通过参数吸收两类 Hero 的差异：窄屏布局（compactLayout）、侧卡压暗（sideDim）、
/// 底部渐变（scrimGradient）与覆盖层定位（overlayWithinCenterCard）。
class MediaHeroCarousel extends StatefulWidget {
  const MediaHeroCarousel({
    required this.entries,
    required this.onOpen,
    required this.heightFor,
    this.sideDim = 0,
    this.scrimGradient = false,
    this.overlayWithinCenterCard = true,
    this.overlayInsets = const EdgeInsets.only(left: 48, right: 48, bottom: 36),
    this.compactLayout = true,
    this.activeIndicatorColor = Colors.white,
    this.inactiveIndicatorColor = const Color(0x5CFFFFFF),
    this.emptyPlaceholder,
    this.imageFallback = const MediaHeroImageFallback(),
    super.key,
  });

  final List<MediaHeroEntry> entries;
  final ValueChanged<String> onOpen;
  final double Function(double width) heightFor;

  /// 侧卡压暗透明度（0 表示不压暗）。
  final double sideDim;

  /// 是否在整幅画布上叠加底部渐变遮罩。
  final bool scrimGradient;

  /// 覆盖层是否收在中央卡片范围内（电影式），否则全宽内边距定位（剧集式）。
  final bool overlayWithinCenterCard;

  /// 全宽覆盖层模式的内边距。
  final EdgeInsets overlayInsets;

  /// 窄屏（<600px）时切换为整幅封面布局。
  final bool compactLayout;

  final Color activeIndicatorColor;
  final Color inactiveIndicatorColor;

  /// 条目为空时的占位内容。
  final Widget? emptyPlaceholder;

  /// 图片加载失败或缺失时的回退。
  final Widget imageFallback;

  static const _switchInterval = Duration(seconds: 30);
  static const _crossfadeDuration = Duration(milliseconds: 500);
  static const _cardFraction = 0.52;
  static const _centerScale = 1.05;
  static const _sideScale = 0.80;
  static const _sideAngle = 0.42;
  static const _perspective = 0.0012;
  static const _sideShiftFraction = 0.32;

  @override
  State<MediaHeroCarousel> createState() => _MediaHeroCarouselState();
}

class _MediaHeroCarouselState extends State<MediaHeroCarousel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  Timer? _timer;
  int _index = 0;
  bool _hovering = false;

  List<MediaHeroEntry> get _entries => widget.entries;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: MediaHeroCarousel._crossfadeDuration,
    );
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant MediaHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_entries.length != oldWidget.entries.length) {
      _index = 0;
      _animCtrl.reset();
      _restartTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    if (_entries.length < 2) return;
    _timer = Timer.periodic(MediaHeroCarousel._switchInterval, (_) {
      if (!mounted || _hovering || _entries.length < 2) return;
      _animateTo(1);
    });
  }

  void _restartTimer() => _startTimer();

  void _animateTo(int delta) {
    if (_entries.length < 2 || _animCtrl.isAnimating) return;
    _animCtrl.reset();
    _animCtrl.forward().then((_) {
      if (!mounted || _entries.length < 2) return;
      setState(() {
        _index = (_index + delta) % _entries.length;
        if (_index < 0) _index += _entries.length;
      });
    });
  }

  void _goToPage(int target) {
    if (_entries.length < 2 || _animCtrl.isAnimating) return;
    final delta = target - _index;
    if (delta == 0) return;
    _animateTo(delta);
  }

  int _sideIndex(int offset) {
    final raw = (_index + offset) % _entries.length;
    return raw < 0 ? raw + _entries.length : raw;
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entries.isEmpty ? null : _entries[_index % _entries.length];
    return LayoutBuilder(
      builder: (context, constraints) {
        final heroHeight = widget.heightFor(constraints.maxWidth);
        final w = constraints.maxWidth;
        final isNarrow = widget.compactLayout && w < 600;
        return MouseRegion(
          cursor: SystemMouseCursors.basic,
          onEnter: (_) => _hovering = true,
          onExit: (_) => _hovering = false,
          child: Container(
            height: heroHeight,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: context.videoColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    Theme.of(context).brightness == Brightness.light
                        ? context.videoColors.outlineVariant.withValues(
                          alpha: 0.40,
                        )
                        : context.videoColors.outlineVariant.withValues(
                          alpha: 0.18,
                        ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.32),
                  blurRadius: 32,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: _buildHeroStack(context, entry, heroHeight, w, isNarrow),
          ),
        );
      },
    );
  }

  Widget _buildHeroStack(
    BuildContext context,
    MediaHeroEntry? entry,
    double heroHeight,
    double w,
    bool isNarrow,
  ) {
    if (_entries.isEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: widget.emptyPlaceholder ?? const SizedBox.expand(),
          ),
        ],
      );
    }

    if (isNarrow) {
      final current = _entries[_index];
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap:
                  current.id.isEmpty ? null : () => widget.onOpen(current.id),
              child: MediaHeroImage(
                backdropUrl: current.backdropUrl,
                posterUrl: current.posterUrl,
                fallback: widget.imageFallback,
              ),
            ),
          ),
          Positioned(left: 16, right: 16, bottom: 24, child: current.overlay),
          Positioned(
            left: 0,
            right: 0,
            bottom: 14,
            child: _MediaCarouselIndicators(
              count: _entries.length,
              current: _index % _entries.length,
              activeColor: widget.activeIndicatorColor,
              inactiveColor: widget.inactiveIndicatorColor,
              onTap: _goToPage,
            ),
          ),
        ],
      );
    }

    final cardWidth = w * MediaHeroCarousel._cardFraction;
    final centerLeft = (w - cardWidth * MediaHeroCarousel._centerScale) / 2;
    final sideShift = cardWidth * MediaHeroCarousel._sideShiftFraction;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_entries.length >= 2)
          _build3DCard(
            left: centerLeft - sideShift,
            cardWidth: cardWidth,
            heroHeight: heroHeight,
            angle: MediaHeroCarousel._sideAngle,
            scale: MediaHeroCarousel._sideScale,
            entry: _entries[_sideIndex(-1)],
            dim: widget.sideDim,
            onTap: () => _animateTo(-1),
          ),
        if (_entries.length >= 2)
          _build3DCard(
            left: centerLeft + sideShift,
            cardWidth: cardWidth,
            heroHeight: heroHeight,
            angle: -MediaHeroCarousel._sideAngle,
            scale: MediaHeroCarousel._sideScale,
            entry: _entries[_sideIndex(1)],
            dim: widget.sideDim,
            onTap: () => _animateTo(1),
          ),
        if (entry != null)
          _build3DCard(
            left: centerLeft,
            cardWidth: cardWidth,
            heroHeight: heroHeight,
            angle: 0,
            scale: MediaHeroCarousel._centerScale,
            entry: entry,
            dim: 0,
            key: ValueKey(_index),
            onTap: entry.id.isEmpty ? null : () => widget.onOpen(entry.id),
          ),
        if (widget.scrimGradient)
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0x00000000),
                      Color(0x14000000),
                      Color(0x44000000),
                      Color(0xAA000000),
                    ],
                    stops: [0.0, 0.3, 0.65, 1.0],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: widget.overlayWithinCenterCard ? centerLeft + 24 : 48,
          right:
              widget.overlayWithinCenterCard
                  ? w -
                      (centerLeft +
                          cardWidth * MediaHeroCarousel._centerScale) +
                      24
                  : 48,
          bottom: widget.overlayWithinCenterCard ? 28 : 36,
          child: entry?.overlay ?? const SizedBox.shrink(),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 14,
          child: _MediaCarouselIndicators(
            count: _entries.length,
            current: _index % _entries.length,
            activeColor: widget.activeIndicatorColor,
            inactiveColor: widget.inactiveIndicatorColor,
            onTap: _goToPage,
          ),
        ),
        if (_hovering && _entries.length >= 2) ...[
          Positioned(
            left: 16,
            top: 0,
            bottom: 0,
            child: _MediaCarouselArrow(
              icon: Icons.chevron_left_rounded,
              onTap: () => _animateTo(-1),
            ),
          ),
          Positioned(
            right: 16,
            top: 0,
            bottom: 0,
            child: _MediaCarouselArrow(
              icon: Icons.chevron_right_rounded,
              onTap: () => _animateTo(1),
            ),
          ),
        ],
      ],
    );
  }

  Widget _build3DCard({
    required double left,
    required double cardWidth,
    required double heroHeight,
    required double angle,
    required double scale,
    required MediaHeroEntry entry,
    required double dim,
    VoidCallback? onTap,
    Key? key,
  }) {
    final scaledW = cardWidth * scale;
    final scaledH = heroHeight * scale;
    return Positioned(
      left: left,
      top: (heroHeight - scaledH) / 2,
      width: scaledW,
      height: scaledH,
      child: Transform(
        alignment: Alignment.center,
        transform:
            Matrix4.identity()
              ..setEntry(3, 2, MediaHeroCarousel._perspective)
              ..rotateY(angle),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            key: key,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: angle == 0 ? 0.18 : 0.10),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: angle == 0 ? 0.40 : 0.22,
                  ),
                  blurRadius: angle == 0 ? 32 : 18,
                  offset: Offset(0, angle == 0 ? 16 : 8),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                MediaHeroImage(
                  backdropUrl: entry.backdropUrl,
                  posterUrl: entry.posterUrl,
                  fallback: widget.imageFallback,
                ),
                if (dim > 0)
                  ColoredBox(color: Colors.black.withValues(alpha: dim)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hero 卡片图片：背景图优先，缺失时回退海报，再缺失时显示回退占位。
class MediaHeroImage extends StatelessWidget {
  const MediaHeroImage({
    required this.fallback,
    this.backdropUrl,
    this.posterUrl,
    super.key,
  });

  final String? backdropUrl;
  final String? posterUrl;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    if (backdropUrl != null) {
      return Image.network(
        backdropUrl!,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        cacheWidth: 800,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }
    if (posterUrl != null) {
      return PosterHeroImage(url: posterUrl!, errorFallback: fallback);
    }
    return fallback;
  }
}

/// Hero 图片加载失败或缺失时的渐变占位。
class MediaHeroImageFallback extends StatelessWidget {
  const MediaHeroImageFallback({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF201F3B), Color(0xFF35213B)],
        ),
      ),
    );
  }
}

class _MediaCarouselIndicators extends StatelessWidget {
  const _MediaCarouselIndicators({
    required this.count,
    required this.current,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final int count;
  final int current;
  final Color activeColor;
  final Color inactiveColor;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < count; i++)
          GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              width: i == current ? 24 : 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: i == current ? activeColor : inactiveColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
      ],
    );
  }
}

class _MediaCarouselArrow extends StatelessWidget {
  const _MediaCarouselArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.40),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}
