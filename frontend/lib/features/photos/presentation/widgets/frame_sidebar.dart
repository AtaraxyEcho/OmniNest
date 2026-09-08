import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/features/photos/application/photo_center_models.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_view_meta.dart';

/// Frame 风格桌面侧栏：系统 Logo、视图导航与图库统计，宽度 220px，可折叠 60px。
class FrameSidebar extends StatelessWidget {
  const FrameSidebar({
    required this.activeView,
    required this.onSelectView,
    required this.photoCount,
    required this.albumCount,
    required this.trashCount,
    required this.collapsed,
    super.key,
  });

  final FrameView activeView;
  final ValueChanged<FrameView> onSelectView;
  final int photoCount;
  final int albumCount;
  final int trashCount;
  final bool collapsed;

  /// 设计稿导航结构：五个主视图 + 收藏，分隔线后为回收站。
  static const List<FrameView> _primaryViews = <FrameView>[
    FrameView.grid,
    FrameView.favorites,
    FrameView.albums,
    FrameView.timeline,
    FrameView.locations,
    FrameView.tags,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.frameColors;
    return AnimatedContainer(
      duration:
          MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      width: collapsed ? 60 : 220,
      decoration: BoxDecoration(
        color: colors.navBg,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Column(
        children: [
          _FrameLogo(collapsed: collapsed),
          Expanded(
            child: SingleChildScrollView(
              // 设计稿 nav 容器 px-2，导航项 w-full 铺满剩余宽度。
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final view in _primaryViews)
                      _FrameNavItem(
                        key: ValueKey('frame-nav-${view.name}'),
                        view: view,
                        label: frameViewLabel(l10n, view),
                        active: activeView == view,
                        collapsed: collapsed,
                        onTap: () => onSelectView(view),
                      ),
                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      height: 1,
                      color: colors.border,
                    ),
                    _FrameNavItem(
                      key: const ValueKey('frame-nav-trash'),
                      view: FrameView.trash,
                      label: frameViewLabel(l10n, FrameView.trash),
                      active: activeView == FrameView.trash,
                      collapsed: collapsed,
                      onTap: () => onSelectView(FrameView.trash),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildStats(context),
        ],
      ),
    );
  }

  Widget _buildStats(BuildContext context) {
    // 设计稿折叠态隐藏统计文本，但保留外层 pb-4 的底部让位。
    if (collapsed) {
      return const SizedBox(height: 16);
    }
    final l10n = AppLocalizations.of(context);
    final colors = context.frameColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.photosFrameStatsPhotos(photoCount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.ink,
              fontSize: AppTypography.bodySmall,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            l10n.photosFrameStatsMeta(albumCount, trashCount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.muted,
              fontSize: AppTypography.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// 侧栏品牌区：系统 Logo + 模块名称，静态展示不可点击。
class _FrameLogo extends StatelessWidget {
  const _FrameLogo({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final colors = context.frameColors;
    final mark = const BrandLogo(size: 28, radius: 8);
    if (collapsed) {
      return SizedBox(height: 60, child: Center(child: mark));
    }
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          const SizedBox(width: 16),
          mark,
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              AppLocalizations.of(context).photosModuleDisplayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: FramePalette.serifFamily,
                fontFamilyFallback: FramePalette.serifFallback,
                color: colors.ink,
                fontSize: AppTypography.titleLarge,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 侧栏导航项：激活强调底色 + 陶土色图标，悬停悬停底色。
class _FrameNavItem extends StatefulWidget {
  const _FrameNavItem({
    required this.view,
    required this.label,
    required this.active,
    required this.collapsed,
    required this.onTap,
    super.key,
  });

  final FrameView view;
  final String label;
  final bool active;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  State<_FrameNavItem> createState() => _FrameNavItemState();
}

class _FrameNavItemState extends State<_FrameNavItem> {
  static const Duration stateDuration = Duration(milliseconds: 150);

  bool _hovering = false;
  Color? _lastIconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.frameColors;
    final active = widget.active;
    // 关键：未悬停端使用"悬停色 + alpha 0"而不是 Colors.transparent，
    // 避免颜色插值时 RGB 向黑色过渡导致进入/移出瞬间闪现暗色背景。
    final background =
        active
            ? colors.activeBg
            : _hovering
            ? colors.hover
            : colors.hover.withValues(alpha: 0);
    final foreground = active || _hovering ? colors.ink : colors.muted;
    final iconColor = active ? colors.accent : foreground;

    _lastIconColor = iconColor;
    Widget item = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Semantics(
          button: true,
          selected: active,
          child: AnimatedContainer(
            duration:
                MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
            height: 35,
            padding:
                widget.collapsed
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(horizontal: 14),
            alignment:
                widget.collapsed ? Alignment.center : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<Color?>(
                  tween: ColorTween(
                    begin: _lastIconColor ?? iconColor,
                    end: iconColor,
                  ),
                  duration: stateDuration,
                  builder:
                      (context, color, child) => Icon(
                        frameViewIcon(widget.view),
                        size: 17,
                        color: color,
                      ),
                ),
                if (!widget.collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: AnimatedDefaultTextStyle(
                      duration: stateDuration,
                      style: TextStyle(
                        color: foreground,
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.13,
                      ),
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (widget.collapsed) {
      item = Tooltip(message: widget.label, child: item);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: item,
    );
  }
}
