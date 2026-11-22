part of 'comic_reader_view.dart';

/// 单页或双页跨页渲染槽。
class _ComicSpreadSlot {
  const _ComicSpreadSlot(
    this.pageIndices, {
    this.isCover = false,
    this.isWideSpread = false,
  });

  final List<int> pageIndices;
  final bool isCover;
  final bool isWideSpread;

  int get startPageIndex => pageIndices.first;
  int get endPageIndex => pageIndices.last;
}

class _ComicPageTurnCallbacks implements PageTurnCallbacks {
  const _ComicPageTurnCallbacks({
    required this.onPageChangedFn,
    required this.onToggleControlsFn,
  });

  final ValueChanged<int> onPageChangedFn;
  final VoidCallback onToggleControlsFn;

  @override
  void onPageChanged(int pageIndex) => onPageChangedFn(pageIndex);

  @override
  void onPreviousChapter() {}

  @override
  void onNextChapter() {}

  @override
  void onToggleControls() => onToggleControlsFn();
}

/// 离屏抓图首帧汇聚器：待当前槽位所有图片首帧绘制完成后派发一次就绪通知。
class _ComicSnapshotSlotTracker {
  _ComicSnapshotSlotTracker(this.expectedFrames);

  final int expectedFrames;
  int _painted = 0;
  bool _dispatched = false;

  void markPainted(BuildContext context) {
    if (_dispatched) return;
    _painted++;
    if (_painted >= expectedFrames) {
      _dispatched = true;
      const ReaderSnapshotFrameReadyNotification().dispatch(context);
    }
  }
}

/// 纯纸面封里（用于封面槽或奇数末页对侧），在离屏抓图态自动于首帧派发就绪通知。
class _ComicEndpaperLeaf extends StatefulWidget {
  const _ComicEndpaperLeaf({
    required this.surfaceColor,
    required this.deskColor,
    this.forSnapshot = false,
  });

  final Color surfaceColor;
  final Color deskColor;
  final bool forSnapshot;

  @override
  State<_ComicEndpaperLeaf> createState() => _ComicEndpaperLeafState();
}

class _ComicEndpaperLeafState extends State<_ComicEndpaperLeaf> {
  @override
  void initState() {
    super.initState();
    if (widget.forSnapshot) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          const ReaderSnapshotFrameReadyNotification().dispatch(context);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        ThemeData.estimateBrightnessForColor(widget.surfaceColor) ==
        Brightness.dark;
    final tint =
        Color.lerp(
          widget.surfaceColor,
          widget.deskColor,
          isDark ? 0.14 : 0.05,
        )!;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(tint, Colors.white, isDark ? 0.02 : 0.08)!, tint],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// Book 模式左右悬浮圆形翻页按钮（48×48 圆形半透明，悬停放大 1.1x，与正文阅读器一致）。
class _ComicBookFloatingArrow extends StatefulWidget {
  const _ComicBookFloatingArrow({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_ComicBookFloatingArrow> createState() =>
      _ComicBookFloatingArrowState();
}

class _ComicBookFloatingArrowState extends State<_ComicBookFloatingArrow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: AnimatedScale(
          scale: _hovered ? 1.1 : 1.0,
          duration: MotionToken.reduced(context, MotionToken.pageSwitch),
          curve: Curves.easeOutBack,
          child: Material(
            color: Colors.white.withValues(alpha: _hovered ? 0.18 : 0.08),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: widget.onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(widget.icon, size: 24, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
