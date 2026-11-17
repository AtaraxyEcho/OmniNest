import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/theme/motion_token.dart';
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bookMode = settings.usesBookDesk;
    final foreground =
        bookMode ? settings.bookDeskTextColor : settings.onSurfaceVariantColor;
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
                  icon: Icons.arrow_back_rounded,
                  label: l10n.readerClose,
                  foreground: foreground,
                  onPressed: onBack,
                  large: true,
                ),
                const SizedBox(width: 10),
                Flexible(
                  flex: 2,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
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
                            fontSize: 17,
                            height: 1.25,
                          ),
                        ),
                        if (chapterTitle.isNotEmpty)
                          Text(
                            chapterTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: foreground.withValues(alpha: 0.6),
                              fontSize: AppTypography.labelMicro,
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
                    onSettingsChanged: onSettingsChanged,
                  ),
                  const SizedBox(width: 10),
                ],
                _DesktopIconButton(
                  icon: Icons.search_rounded,
                  label: l10n.readerSearchInBook,
                  foreground: foreground,
                  onPressed: onSearch,
                ),
                _DesktopIconButton(
                  icon: Icons.list_rounded,
                  label: l10n.readerTableOfContents,
                  foreground: foreground,
                  onPressed: onShowContents,
                ),
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
                  selected: isBookmarked,
                  onPressed: onAddBookmark,
                ),
                _DesktopIconButton(
                  icon: Icons.edit_note_rounded,
                  label: l10n.readerAnnotations,
                  foreground: foreground,
                  onPressed: onShowAnnotations,
                ),
                _DesktopIconButton(
                  icon: Icons.text_fields_rounded,
                  label: l10n.readerSettingsTitle,
                  foreground: foreground,
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
    required this.onSettingsChanged,
  });

  final ReaderViewSettings settings;
  final Color foreground;
  final ValueChanged<ReaderViewSettings>? onSettingsChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final background =
        settings.usesBookDesk
            ? Colors.white.withValues(alpha: 0.08)
            : settings.onSurfaceColor.withValues(alpha: 0.08);
    final line =
        settings.usesBookDesk
            ? Colors.white.withValues(alpha: 0.12)
            : settings.onSurfaceColor.withValues(alpha: 0.12);
    final active =
        settings.usesBookDesk
            ? Colors.white.withValues(alpha: 0.2)
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
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (id, label, icon) in options)
            Tooltip(
              message: label,
              child: Semantics(
                button: true,
                selected: mode == id,
                label: label,
                child: InkWell(
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
                  borderRadius: BorderRadius.circular(6),
                  child: AnimatedContainer(
                    duration: MotionToken.resolve(context, MotionToken.fast),
                    curve: MotionToken.curve,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: mode == id ? active : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 15, color: foreground),
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: TextStyle(
                            color: foreground,
                            fontSize: AppTypography.labelSmall,
                            fontWeight:
                                mode == id ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DesktopIconButton extends StatelessWidget {
  const _DesktopIconButton({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.onPressed,
    this.selected = false,
    this.large = false,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final VoidCallback? onPressed;
  final bool selected;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(7),
            child: SizedBox(
              width: large ? 40 : 36,
              height: 36,
              child: Icon(
                icon,
                size: large ? 20 : 18,
                color:
                    onPressed == null
                        ? foreground.withValues(alpha: 0.35)
                        : foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
