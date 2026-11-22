import 'package:material_ui/material_ui.dart';
import 'package:omninest/app/desktop/widgets/desktop_window_controls.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_panel_coordinator.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

enum _ReaderTopIcon {
  left,
  book,
  swipe,
  scroll,
  search,
  list2,
  bookmark,
  highlight,
  type,
}

/// 桌面原型 `.bk-top`（v5 全宽底层拖拽标准化）：
/// - 64px 全宽底层 `DesktopWindowDragRegion` 支持任意空白区窗口拖拽与双击最大化；
/// - 上层左右按钮与模式胶囊作为独立兄弟节点脱离 `onDoubleTap` 竞技场，0ms 响应且绝不误触最大化；
/// - 单个 Expanded 占满中段弹性空白，模式胶囊与 5 枚细线矢量工具图标严格锚定右缘 20px。
class ReaderDesktopTopBar extends StatelessWidget {
  const ReaderDesktopTopBar({
    required this.settings,
    required this.bookTitle,
    required this.chapterTitle,
    required this.onBack,
    required this.onSearch,
    required this.onShowContents,
    required this.onAddBookmark,
    required this.onShowAnnotations,
    required this.onShowSettings,
    required this.onSettingsChanged,
    required this.isBookmarked,
    required this.pageModeEnabled,
    this.activePanel,
    this.annotationBadgeCount = 0,
    super.key,
  });

  final ReaderViewSettings settings;
  final String bookTitle;
  final String chapterTitle;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback? onShowContents;
  final VoidCallback? onAddBookmark;
  final VoidCallback? onShowAnnotations;
  final VoidCallback? onShowSettings;
  final ValueChanged<ReaderViewSettings>? onSettingsChanged;
  final bool isBookmarked;
  final bool pageModeEnabled;
  final ReaderPanelType? activePanel;
  final int annotationBadgeCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bookMode = settings.usesBookDesk;
    final foreground =
        bookMode ? settings.bookDeskTextColor : settings.onSurfaceColor;
    final muted =
        bookMode
            ? settings.bookDeskTextColor.withValues(alpha: 0.62)
            : settings.onSurfaceVariantColor;
    final compactModeLabels = MediaQuery.sizeOf(context).width < 960;

    return SafeArea(
      bottom: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient:
              bookMode
                  ? null
                  : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      settings.surfaceColor.withValues(alpha: 0.96),
                      settings.surfaceColor.withValues(alpha: 0),
                    ],
                    stops: const [0.7, 1],
                  ),
        ),
        child: SizedBox(
          height: 64,
          child: Stack(
            children: [
              // 64px 全宽底层窗口拖拽区：任意空白区域均可拖动窗口与双击最大化，
              // 上层按钮与模式胶囊作为独立兄弟节点保持 0ms 响应。
              const Positioned.fill(
                child: DesktopWindowDragRegion(child: SizedBox.expand()),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _DesktopIconButton(
                      icon: _ReaderTopIcon.left,
                      label: l10n.readerClose,
                      foreground: foreground,
                      accent: settings.accentColor,
                      bookMode: bookMode,
                      onPressed: onBack,
                      large: true,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: IgnorePointer(
                        child: SizedBox(
                          height: 64,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: compactModeLabels ? 180 : 300,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    bookTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: foreground,
                                      fontFamily: AppTypography.serifFamily,
                                      fontFamilyFallback:
                                          AppTypography.serifFamilyFallback,
                                      fontSize:
                                          17, // ignore: font_size_whitelist
                                      fontWeight: FontWeight.w400,
                                      height: 1.25,
                                    ),
                                  ),
                                  if (chapterTitle.isNotEmpty)
                                    Text(
                                      chapterTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: muted,
                                        fontSize:
                                            12, // ignore: font_size_whitelist
                                        height: 1.3,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (pageModeEnabled) ...[
                      _DesktopModeSwitch(
                        settings: settings,
                        foreground: foreground,
                        bookMode: bookMode,
                        iconOnly: compactModeLabels,
                        onSettingsChanged: onSettingsChanged,
                      ),
                      const SizedBox(width: 10),
                    ],
                    _DesktopIconButton(
                      icon: _ReaderTopIcon.search,
                      label: '${l10n.readerSearchInBook} (/)',
                      foreground: foreground,
                      accent: settings.accentColor,
                      bookMode: bookMode,
                      selected: activePanel == ReaderPanelType.search,
                      onPressed: onSearch,
                    ),
                    const SizedBox(width: 4),
                    _DesktopIconButton(
                      icon: _ReaderTopIcon.list2,
                      label: '${l10n.readerTableOfContents} (T)',
                      foreground: foreground,
                      accent: settings.accentColor,
                      bookMode: bookMode,
                      selected: activePanel == ReaderPanelType.contents,
                      onPressed: onShowContents,
                    ),
                    const SizedBox(width: 4),
                    _DesktopIconButton(
                      icon: _ReaderTopIcon.bookmark,
                      filled: isBookmarked,
                      label:
                          isBookmarked
                              ? l10n.readerRemoveBookmark
                              : l10n.readerAddBookmark,
                      foreground: foreground,
                      accent: settings.accentColor,
                      bookMode: bookMode,
                      selected: isBookmarked,
                      onPressed: onAddBookmark,
                    ),
                    const SizedBox(width: 4),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _DesktopIconButton(
                          icon: _ReaderTopIcon.highlight,
                          label: l10n.readerAnnotations,
                          foreground: foreground,
                          accent: settings.accentColor,
                          bookMode: bookMode,
                          selected: activePanel == ReaderPanelType.annotations,
                          onPressed: onShowAnnotations,
                        ),
                        if (annotationBadgeCount > 0)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: IgnorePointer(
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 16),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: settings.accentColor,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  annotationBadgeCount > 99
                                      ? '99+'
                                      : '$annotationBadgeCount',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: ReaderReadingPalette.onAccentInk,
                                    fontSize: 10, // ignore: font_size_whitelist
                                    fontWeight: FontWeight.w700,
                                    height: 1.15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    _DesktopIconButton(
                      icon: _ReaderTopIcon.type,
                      label: l10n.readerSettingsTitle,
                      foreground: foreground,
                      accent: settings.accentColor,
                      bookMode: bookMode,
                      selected: activePanel == ReaderPanelType.settings,
                      onPressed: onShowSettings,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopModeSwitch extends StatelessWidget {
  const _DesktopModeSwitch({
    required this.settings,
    required this.foreground,
    required this.bookMode,
    required this.iconOnly,
    required this.onSettingsChanged,
  });

  final ReaderViewSettings settings;
  final Color foreground;
  final bool bookMode;
  final bool iconOnly;
  final ValueChanged<ReaderViewSettings>? onSettingsChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final background =
        bookMode
            ? Colors.white.withValues(alpha: 0.08)
            : settings.onSurfaceColor.withValues(alpha: 0.08);
    final line =
        bookMode
            ? Colors.white.withValues(alpha: 0.12)
            : settings.onSurfaceColor.withValues(alpha: 0.12);
    final activeBg =
        bookMode
            ? Colors.white.withValues(alpha: 0.20)
            : settings.onSurfaceColor.withValues(alpha: 0.14);
    final mode =
        settings.readingMode == 'scroll'
            ? 'scroll'
            : settings.pageTurnMode == 'slide'
            ? 'swipe'
            : 'book';
    final options = [
      ('book', l10n.readerModeBook, _ReaderTopIcon.book),
      ('swipe', l10n.readerModeSwipe, _ReaderTopIcon.swipe),
      ('scroll', l10n.readerModeScroll, _ReaderTopIcon.scroll),
    ];

    final activeIndex = mode == 'scroll' ? 2 : (mode == 'swipe' ? 1 : 0);
    // 等宽单格 + AnimatedPositioned 滑动高亮胶囊：中英文均像素级精准滑行不错位。
    final tabWidth = iconOnly ? 34.0 : 72.0;
    final slideDur = MotionToken.reduced(
      context,
      const Duration(milliseconds: 220),
    );

    return AnimatedContainer(
      duration: slideDur,
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(11),
      ),
      child: SizedBox(
        width: tabWidth * options.length,
        height: 28,
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: slideDur,
              curve: const Cubic(0.22, 1.0, 0.36, 1.0),
              left: activeIndex * tabWidth,
              top: 0,
              bottom: 0,
              width: tabWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: activeBg,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            Row(
              children: [
                for (final (id, label, icon) in options)
                  SizedBox(
                    width: tabWidth,
                    child: _ModeSwitchTab(
                      label: label,
                      icon: icon,
                      selected: mode == id,
                      iconOnly: iconOnly,
                      foreground: foreground,
                      activeBg: Colors.transparent,
                      onTap: () {
                        if (id == 'scroll') {
                          onSettingsChanged?.call(
                            settings.copyWith(readingMode: 'scroll'),
                          );
                        } else {
                          onSettingsChanged?.call(
                            settings.copyWith(
                              readingMode: 'page',
                              pageTurnMode: id == 'book' ? 'cover' : 'slide',
                            ),
                          );
                        }
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeSwitchTab extends StatefulWidget {
  const _ModeSwitchTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.iconOnly,
    required this.foreground,
    required this.activeBg,
    required this.onTap,
  });

  final String label;
  final _ReaderTopIcon icon;
  final bool selected;
  final bool iconOnly;
  final Color foreground;
  final Color activeBg;
  final VoidCallback onTap;

  @override
  State<_ModeSwitchTab> createState() => _ModeSwitchTabState();
}

class _ModeSwitchTabState extends State<_ModeSwitchTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color =
        widget.selected || _hovered
            ? widget.foreground
            : widget.foreground.withValues(alpha: 0.65);
    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: MotionToken.resolve(context, MotionToken.fast),
            curve: MotionToken.curve,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.selected ? widget.activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ReaderLineIcon(widget.icon, size: 15, color: color),
                if (!widget.iconOnly) ...[
                  const SizedBox(width: 6),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12.5, // ignore: font_size_whitelist
                      fontWeight:
                          widget.selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopIconButton extends StatefulWidget {
  const _DesktopIconButton({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.accent,
    required this.bookMode,
    required this.onPressed,
    this.selected = false,
    this.filled = false,
    this.large = false,
  });

  final _ReaderTopIcon icon;
  final String label;
  final Color foreground;
  final Color accent;
  final bool bookMode;
  final VoidCallback? onPressed;
  final bool selected;
  final bool filled;
  final bool large;

  @override
  State<_DesktopIconButton> createState() => _DesktopIconButtonState();
}

class _DesktopIconButtonState extends State<_DesktopIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final hoverBg =
        widget.bookMode
            ? Colors.white.withValues(alpha: 0.12)
            : widget.foreground.withValues(alpha: 0.10);
    final selectedBg =
        widget.bookMode
            ? widget.accent.withValues(alpha: 0.18)
            : widget.accent.withValues(alpha: 0.14);

    final bg =
        !enabled
            ? Colors.transparent
            : widget.selected
            ? selectedBg
            : _hovered
            ? hoverBg
            : Colors.transparent;

    final fg =
        !enabled
            ? widget.foreground.withValues(alpha: 0.35)
            : widget.selected
            ? widget.accent
            : _hovered
            ? widget.foreground
            : widget.foreground.withValues(alpha: 0.84);

    final side = widget.large ? 40.0 : 34.0;
    final radius = widget.large ? 12.0 : 9.0;

    return Tooltip(
      message: widget.label,
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: widget.label,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit:
              (_) => setState(() {
                _hovered = false;
                _pressed = false;
              }),
          child: GestureDetector(
            onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
            onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
            onTapCancel:
                enabled ? () => setState(() => _pressed = false) : null,
            onTap: widget.onPressed,
            behavior: HitTestBehavior.opaque,
            child: AnimatedScale(
              scale: _pressed ? 0.88 : 1.0,
              duration: MotionToken.resolve(context, MotionToken.fast),
              curve: Curves.easeOutBack,
              child: AnimatedContainer(
                duration: MotionToken.resolve(context, MotionToken.fast),
                width: side,
                height: side,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: Center(
                  child: _ReaderLineIcon(
                    widget.icon,
                    size: widget.large ? 20 : 17,
                    color: fg,
                    filled: widget.filled,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 1:1 移植样例 `icons.tsx` 的 24×24 细线矢量图标（strokeWidth: 1.65, round cap/join）。
class _ReaderLineIcon extends StatelessWidget {
  const _ReaderLineIcon(
    this.glyph, {
    required this.size,
    required this.color,
    this.filled = false,
  });

  final _ReaderTopIcon glyph;
  final double size;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ReaderLineIconPainter(
        glyph: glyph,
        color: color,
        filled: filled,
      ),
    );
  }
}

class _ReaderLineIconPainter extends CustomPainter {
  const _ReaderLineIconPainter({
    required this.glyph,
    required this.color,
    required this.filled,
  });

  final _ReaderTopIcon glyph;
  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24.0;
    canvas.save();
    canvas.scale(s, s);
    final stroke =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.65
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    switch (glyph) {
      case _ReaderTopIcon.left:
        canvas.drawPath(
          Path()
            ..moveTo(15, 5)
            ..lineTo(8, 12)
            ..lineTo(15, 19),
          stroke,
        );
      case _ReaderTopIcon.book:
        final left =
            Path()
              ..moveTo(4, 5.5)
              ..cubicTo(4, 3.6, 5.6, 2, 7.5, 2)
              ..lineTo(12, 2)
              ..lineTo(12, 20)
              ..lineTo(7.5, 20)
              ..cubicTo(5.6, 20, 4, 21.3, 4, 22.5)
              ..close();
        final right =
            Path()
              ..moveTo(20, 5.5)
              ..cubicTo(20, 3.6, 18.4, 2, 16.5, 2)
              ..lineTo(12, 2)
              ..lineTo(12, 20)
              ..lineTo(16.5, 20)
              ..cubicTo(18.4, 20, 20, 21.3, 20, 22.5)
              ..close();
        canvas
          ..drawPath(left, stroke)
          ..drawPath(right, stroke);
      case _ReaderTopIcon.swipe:
        canvas
          ..drawLine(const Offset(3, 12), const Offset(21, 12), stroke)
          ..drawPath(
            Path()
              ..moveTo(8, 7)
              ..lineTo(3, 12)
              ..lineTo(8, 17),
            stroke,
          )
          ..drawPath(
            Path()
              ..moveTo(16, 7)
              ..lineTo(21, 12)
              ..lineTo(16, 17),
            stroke,
          );
      case _ReaderTopIcon.scroll:
        canvas
          ..drawLine(const Offset(12, 3), const Offset(12, 21), stroke)
          ..drawPath(
            Path()
              ..moveTo(7, 8)
              ..lineTo(12, 3)
              ..lineTo(17, 8),
            stroke,
          )
          ..drawPath(
            Path()
              ..moveTo(7, 16)
              ..lineTo(12, 21)
              ..lineTo(17, 16),
            stroke,
          );
      case _ReaderTopIcon.search:
        canvas
          ..drawCircle(const Offset(11, 11), 7, stroke)
          ..drawLine(const Offset(16.5, 16.5), const Offset(21, 21), stroke);
      case _ReaderTopIcon.list2:
        canvas
          ..drawLine(const Offset(4, 6), const Offset(20, 6), stroke)
          ..drawLine(const Offset(4, 10), const Offset(20, 10), stroke)
          ..drawLine(const Offset(4, 14), const Offset(14, 14), stroke)
          ..drawLine(const Offset(4, 18), const Offset(11, 18), stroke);
      case _ReaderTopIcon.bookmark:
        final bm =
            Path()
              ..moveTo(6, 3)
              ..lineTo(18, 3)
              ..lineTo(18, 21)
              ..lineTo(12, 17)
              ..lineTo(6, 21)
              ..close();
        if (filled) {
          canvas.drawPath(
            bm,
            Paint()
              ..color = color
              ..style = PaintingStyle.fill,
          );
        }
        canvas.drawPath(bm, stroke);
      case _ReaderTopIcon.highlight:
        canvas
          ..drawPath(
            Path()
              ..moveTo(4, 20)
              ..lineTo(8, 19)
              ..lineTo(19, 8)
              ..arcToPoint(
                const Offset(16, 5),
                radius: const Radius.circular(2.1),
                clockwise: false,
              )
              ..lineTo(5, 16)
              ..close(),
            stroke,
          )
          ..drawLine(const Offset(13.5, 7.5), const Offset(16.5, 10.5), stroke)
          ..drawLine(const Offset(13, 20), const Offset(21, 20), stroke);
      case _ReaderTopIcon.type:
        canvas
          ..drawPath(
            Path()
              ..moveTo(4, 7)
              ..lineTo(4, 5)
              ..lineTo(20, 5)
              ..lineTo(20, 7),
            stroke,
          )
          ..drawLine(const Offset(12, 5), const Offset(12, 19), stroke)
          ..drawLine(const Offset(9, 19), const Offset(15, 19), stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ReaderLineIconPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.color != color ||
      oldDelegate.filled != filled;
}
