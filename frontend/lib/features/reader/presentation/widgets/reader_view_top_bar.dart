import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 顶栏溢出菜单动作：紧凑/中等档收纳低频操作（对齐漫画阅读器顶栏先例）。
enum _ReaderTopBarOverflowAction { tts, annotations, shortcuts, immersive }

/// 阅读器顶部上下文栏，按可用宽度收起低频操作。
class ReaderViewTopBar extends StatelessWidget {
  const ReaderViewTopBar({
    required this.settings,
    required this.bookTitle,
    required this.chapterTitle,
    required this.onBack,
    required this.onSearch,
    required this.onShowShortcuts,
    required this.onAddBookmark,
    this.onToggleBookshelf,
    this.onToggleTts,
    this.onShowAnnotations,
    this.onToggleImmersive,
    this.isBookmarked = false,
    this.isInBookshelf = false,
    super.key,
  });

  final ReaderViewSettings settings;
  final String bookTitle;
  final String chapterTitle;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback onShowShortcuts;
  final VoidCallback? onAddBookmark;
  final VoidCallback? onToggleBookshelf;
  final VoidCallback? onToggleTts;
  final VoidCallback? onShowAnnotations;
  final VoidCallback? onToggleImmersive;
  final bool isBookmarked;
  final bool isInBookshelf;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ColoredBox(
        color: settings.controlSurfaceColor.withValues(alpha: 0.97),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final layout = ReaderControlLayout.resolve(
              viewport: Size(
                constraints.maxWidth,
                MediaQuery.sizeOf(context).height,
              ),
              fontSize: settings.fontSize,
              textScale: textScale,
            );
            final barHeight =
                (56 + ((textScale - 1) * 16).clamp(0, 16)).toDouble();
            return SizedBox(
              height: barHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: AppLocalizations.of(context).coreBack,
                      onPressed: onBack,
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: settings.onSurfaceColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(child: _buildTitle()),
                    _TopBarButton(
                      icon:
                          isBookmarked
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                      onTap: onAddBookmark,
                      settings: settings,
                      selected: isBookmarked,
                      tooltip:
                          isBookmarked
                              ? AppLocalizations.of(
                                context,
                              ).readerRemoveBookmark
                              : AppLocalizations.of(context).readerAddBookmark,
                    ),
                    _TopBarButton(
                      icon: Icons.search_rounded,
                      onTap: onSearch,
                      settings: settings,
                      tooltip:
                          AppLocalizations.of(
                            context,
                          ).readerSearchCurrentChapter,
                    ),
                    if (layout.density == ReaderControlDensity.expanded) ...[
                      if (onToggleTts != null)
                        _TopBarButton(
                          icon: Icons.record_voice_over_rounded,
                          onTap: onToggleTts,
                          settings: settings,
                          tooltip: AppLocalizations.of(context).readerReadAloud,
                        ),
                      if (onShowAnnotations != null)
                        _TopBarButton(
                          icon: Icons.edit_note_rounded,
                          onTap: onShowAnnotations,
                          settings: settings,
                          tooltip:
                              AppLocalizations.of(context).readerAnnotations,
                        ),
                    ],
                    if (onToggleBookshelf != null)
                      _TopBarButton(
                        icon:
                            isInBookshelf
                                ? Icons.collections_bookmark_rounded
                                : Icons.collections_bookmark_outlined,
                        onTap: onToggleBookshelf,
                        settings: settings,
                        selected: isInBookshelf,
                        tooltip:
                            isInBookshelf
                                ? AppLocalizations.of(
                                  context,
                                ).readerRemoveFromBookshelf
                                : AppLocalizations.of(
                                  context,
                                ).readerAddToBookshelf,
                      ),
                    if (layout.density == ReaderControlDensity.expanded)
                      _TopBarButton(
                        icon: Icons.keyboard_rounded,
                        onTap: onShowShortcuts,
                        settings: settings,
                        tooltip:
                            AppLocalizations.of(context).readerShortcutsTitle,
                      )
                    else
                      PopupMenuButton<_ReaderTopBarOverflowAction>(
                        tooltip:
                            MaterialLocalizations.of(context).moreButtonTooltip,
                        icon: Icon(
                          Icons.more_vert_rounded,
                          color: settings.onSurfaceVariantColor,
                        ),
                        onSelected: (action) {
                          switch (action) {
                            case _ReaderTopBarOverflowAction.tts:
                              onToggleTts?.call();
                            case _ReaderTopBarOverflowAction.annotations:
                              onShowAnnotations?.call();
                            case _ReaderTopBarOverflowAction.shortcuts:
                              onShowShortcuts();
                            case _ReaderTopBarOverflowAction.immersive:
                              onToggleImmersive?.call();
                          }
                        },
                        itemBuilder:
                            (context) => [
                              if (onToggleTts != null)
                                PopupMenuItem(
                                  value: _ReaderTopBarOverflowAction.tts,
                                  child: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).readerReadAloud,
                                  ),
                                ),
                              if (onShowAnnotations != null)
                                PopupMenuItem(
                                  value:
                                      _ReaderTopBarOverflowAction.annotations,
                                  child: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).readerAnnotations,
                                  ),
                                ),
                              PopupMenuItem(
                                value: _ReaderTopBarOverflowAction.shortcuts,
                                child: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).readerShortcutsTitle,
                                ),
                              ),
                              if (onToggleImmersive != null)
                                PopupMenuItem(
                                  value: _ReaderTopBarOverflowAction.immersive,
                                  child: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).readerImmersiveMode,
                                  ),
                                ),
                            ],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          bookTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: settings.onSurfaceColor,
            fontSize: AppTypography.titleMedium,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (chapterTitle.isNotEmpty)
          Text(
            chapterTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: settings.onSurfaceVariantColor,
              fontSize: AppTypography.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _TopBarButton extends StatelessWidget {
  const _TopBarButton({
    required this.icon,
    required this.onTap,
    required this.settings,
    required this.tooltip,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final ReaderViewSettings settings;
  final String tooltip;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(
        foregroundColor:
            selected ? settings.accentColor : settings.onSurfaceVariantColor,
        backgroundColor:
            selected
                ? settings.accentColor.withValues(alpha: 0.12)
                : Colors.transparent,
        shape: const CircleBorder(),
      ),
      icon: Icon(icon, size: 21),
    );
  }
}
