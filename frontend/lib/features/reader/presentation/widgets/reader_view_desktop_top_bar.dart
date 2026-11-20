import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_panel_coordinator.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 桌面原型 `.bk-top`：左侧返回与书名，右侧模式分段和阅读工具。
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
    final compactModeLabels = MediaQuery.sizeOf(context).width < 1000;

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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _DesktopIconButton(
                  icon: Icons.chevron_left_rounded,
                  label: l10n.readerClose,
                  foreground: foreground,
                  accent: settings.accentColor,
                  bookMode: bookMode,
                  onPressed: onBack,
                  large: true,
                ),
                const SizedBox(width: 10),
                Flexible(
                  flex: 2,
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
                            fontSize: 17, // ignore: font_size_whitelist
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
                              fontSize: 12, // ignore: font_size_whitelist
                              height: 1.3,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                if (pageModeEnabled) ...[
                  _DesktopModeSwitch(
                    settings: settings,
                    foreground: foreground,
                    bookMode: bookMode,
                    iconOnly: compactModeLabels,
                    onSettingsChanged: onSettingsChanged,
                  ),
                  const SizedBox(width: 8),
                ],
                _DesktopIconButton(
                  icon: Icons.search_rounded,
                  label: '${l10n.readerSearchInBook} (/)',
                  foreground: foreground,
                  accent: settings.accentColor,
                  bookMode: bookMode,
                  selected: activePanel == ReaderPanelType.search,
                  onPressed: onSearch,
                ),
                const SizedBox(width: 4),
                _DesktopIconButton(
                  icon: Icons.format_list_bulleted_rounded,
                  label: '${l10n.readerTableOfContents} (T)',
                  foreground: foreground,
                  accent: settings.accentColor,
                  bookMode: bookMode,
                  selected: activePanel == ReaderPanelType.contents,
                  onPressed: onShowContents,
                ),
                const SizedBox(width: 4),
                _DesktopIconButton(
                  icon:
                      isBookmarked
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
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
                      icon: Icons.edit_note_rounded,
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
                  icon: Icons.text_fields_rounded,
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
      ('book', l10n.readerModeBook, Icons.menu_book_rounded),
      ('swipe', l10n.readerModeSwipe, Icons.swap_horiz_rounded),
      ('scroll', l10n.readerModeScroll, Icons.swap_vert_rounded),
    ];

    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (id, label, icon) in options)
            _ModeSwitchTab(
              label: label,
              icon: icon,
              selected: mode == id,
              iconOnly: iconOnly,
              foreground: foreground,
              activeBg: activeBg,
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
        ],
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
  final IconData icon;
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
            height: 30,
            padding: EdgeInsets.symmetric(horizontal: widget.iconOnly ? 8 : 11),
            decoration: BoxDecoration(
              color: widget.selected ? widget.activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 15, color: color),
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
    this.large = false,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color accent;
  final bool bookMode;
  final VoidCallback? onPressed;
  final bool selected;
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
                child: Icon(
                  widget.icon,
                  size: widget.large ? 22 : 18,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
