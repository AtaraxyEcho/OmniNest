import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 顶栏溢出菜单动作：紧凑/中等档收纳低频操作（对齐漫画阅读器顶栏先例）；
/// 样例皮肤的 more 菜单在此基础上额外承载书签/章内搜索/书架。
enum _ReaderTopBarOverflowAction {
  tts,
  annotations,
  shortcuts,
  immersive,
  bookmark,
  search,
  bookshelf,
}

/// 阅读器顶部上下文栏，按可用宽度收起低频操作。
///
/// [sampleChrome] 为样例 ReaderFocus 皮肤（移动壳层）：透明底 + 顶部
/// 轻渐隐、玻璃圆钮返回、居中「书名 + 章节行」、右端 more 玻璃圆钮
/// 承载全部低频操作；默认 false 维持工位实底皮肤。
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
    this.sampleChrome = false,
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

  /// 样例 ReaderFocus 皮肤（移动壳层玻璃 chrome）。
  final bool sampleChrome;

  @override
  Widget build(BuildContext context) {
    if (sampleChrome) {
      return _ReaderSampleTopBar(bar: this);
    }
    return ColoredBox(
      color: settings.controlSurfaceColor.withValues(alpha: 0.97),
      child: SafeArea(
        bottom: false,
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
                        size: 21,
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
                          icon: Icons.graphic_eq_rounded,
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
                                ? Icons.library_add_check_outlined
                                : Icons.library_add_outlined,
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
                        color: settings.controlSurfaceColor,
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
                            // 样例皮肤独有条目：工位菜单不提供，理论不可达，
                            // 仅为 switch 穷尽性兜底。
                            case _ReaderTopBarOverflowAction.bookmark:
                              onAddBookmark?.call();
                            case _ReaderTopBarOverflowAction.search:
                              onSearch();
                            case _ReaderTopBarOverflowAction.bookshelf:
                              onToggleBookshelf?.call();
                          }
                        },
                        itemBuilder:
                            (context) => [
                              if (onToggleTts != null)
                                _menuItem(
                                  _ReaderTopBarOverflowAction.tts,
                                  Icons.graphic_eq_rounded,
                                  AppLocalizations.of(context).readerReadAloud,
                                ),
                              if (onShowAnnotations != null)
                                _menuItem(
                                  _ReaderTopBarOverflowAction.annotations,
                                  Icons.edit_note_rounded,
                                  AppLocalizations.of(
                                    context,
                                  ).readerAnnotations,
                                ),
                              _menuItem(
                                _ReaderTopBarOverflowAction.shortcuts,
                                Icons.keyboard_rounded,
                                AppLocalizations.of(
                                  context,
                                ).readerShortcutsTitle,
                              ),
                              if (onToggleImmersive != null)
                                _menuItem(
                                  _ReaderTopBarOverflowAction.immersive,
                                  Icons.fullscreen_rounded,
                                  AppLocalizations.of(
                                    context,
                                  ).readerImmersiveMode,
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

  /// 溢出菜单条目：图标与直显按钮同款，版式对齐漫画阅读器顶栏。
  PopupMenuItem<_ReaderTopBarOverflowAction> _menuItem(
    _ReaderTopBarOverflowAction value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: settings.onSurfaceVariantColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: settings.onSurfaceColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    // 固定栏只显示本章章节名；书名为空时再退回书名。
    final primary = chapterTitle.isNotEmpty ? chapterTitle : bookTitle;
    return Text(
      primary,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: settings.onSurfaceColor,
        fontSize: AppTypography.titleMedium,
        fontWeight: FontWeight.w700,
      ),
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

/// 样例 ReaderFocus 顶栏：透明底 + 顶部轻渐隐 + 玻璃圆钮 + 居中双行标题。
class _ReaderSampleTopBar extends StatelessWidget {
  const _ReaderSampleTopBar({required this.bar});

  final ReaderViewTopBar bar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      bottom: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              bar.settings.surfaceColor.withValues(alpha: 0.62),
              bar.settings.surfaceColor.withValues(alpha: 0),
            ],
          ),
        ),
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              children: [
                _ReaderGlassCircleButton(
                  icon: OmniIcons.arrow,
                  tooltip: l10n.coreBack,
                  settings: bar.settings,
                  onTap: bar.onBack,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          bar.bookTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: bar.settings.onSurfaceColor,
                            fontSize: AppTypography.bodyMedium,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        if (bar.chapterTitle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              bar.chapterTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: bar.settings.onSurfaceVariantColor,
                                // ignore: font_size_whitelist
                                fontSize: 9,
                                height: 1.3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                _ReaderSampleOverflowMenu(bar: bar),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 样例 more 玻璃圆钮：低频操作全部收纳进溢出菜单。
class _ReaderSampleOverflowMenu extends StatelessWidget {
  const _ReaderSampleOverflowMenu({required this.bar});

  final ReaderViewTopBar bar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    PopupMenuItem<_ReaderTopBarOverflowAction> menuItem(
      _ReaderTopBarOverflowAction value,
      IconData icon,
      String label,
    ) {
      return PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 20, color: bar.settings.onSurfaceVariantColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: bar.settings.onSurfaceColor),
              ),
            ),
          ],
        ),
      );
    }

    return PopupMenuButton<_ReaderTopBarOverflowAction>(
      tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
      color: bar.settings.surfaceColor,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      icon: _ReaderGlassCircleButton(
        icon: OmniIcons.more,
        tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
        settings: bar.settings,
        onTap: null,
      ),
      onSelected: (action) {
        switch (action) {
          case _ReaderTopBarOverflowAction.bookmark:
            bar.onAddBookmark?.call();
          case _ReaderTopBarOverflowAction.search:
            bar.onSearch();
          case _ReaderTopBarOverflowAction.tts:
            bar.onToggleTts?.call();
          case _ReaderTopBarOverflowAction.annotations:
            bar.onShowAnnotations?.call();
          case _ReaderTopBarOverflowAction.bookshelf:
            bar.onToggleBookshelf?.call();
          case _ReaderTopBarOverflowAction.shortcuts:
            bar.onShowShortcuts();
          case _ReaderTopBarOverflowAction.immersive:
            bar.onToggleImmersive?.call();
        }
      },
      itemBuilder:
          (context) => [
            menuItem(
              _ReaderTopBarOverflowAction.bookmark,
              Icons.bookmark_rounded,
              bar.isBookmarked
                  ? l10n.readerRemoveBookmark
                  : l10n.readerAddBookmark,
            ),
            menuItem(
              _ReaderTopBarOverflowAction.search,
              Icons.search_rounded,
              l10n.readerSearchCurrentChapter,
            ),
            if (bar.onToggleTts != null)
              menuItem(
                _ReaderTopBarOverflowAction.tts,
                Icons.graphic_eq_rounded,
                l10n.readerReadAloud,
              ),
            if (bar.onShowAnnotations != null)
              menuItem(
                _ReaderTopBarOverflowAction.annotations,
                Icons.edit_note_rounded,
                l10n.readerAnnotations,
              ),
            if (bar.onToggleBookshelf != null)
              menuItem(
                _ReaderTopBarOverflowAction.bookshelf,
                Icons.library_add_outlined,
                bar.isInBookshelf
                    ? l10n.readerRemoveFromBookshelf
                    : l10n.readerAddToBookshelf,
              ),
            menuItem(
              _ReaderTopBarOverflowAction.shortcuts,
              Icons.keyboard_rounded,
              l10n.readerShortcutsTitle,
            ),
          ],
    );
  }
}

/// 样例 icon-button：48 圆形玻璃钮（调色板底 32% + 10% 描边 + blur 16）。
class _ReaderGlassCircleButton extends StatelessWidget {
  const _ReaderGlassCircleButton({
    required this.icon,
    required this.tooltip,
    required this.settings,
    required this.onTap,
  });

  final OmniIconsData icon;
  final String tooltip;
  final ReaderViewSettings settings;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: settings.surfaceColor.withValues(alpha: 0.32),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: settings.onSurfaceColor.withValues(alpha: 0.10),
                  ),
                ),
                child: Center(
                  child: OmniIcon(
                    icon: icon,
                    size: 20,
                    color: settings.onSurfaceColor,
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
