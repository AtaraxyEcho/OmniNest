import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/photos/application/photo_center_models.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_view_meta.dart';

/// Frame 风格移动端底部导航：视图入口，不含回收站（与设计稿一致）。
class FrameBottomNav extends StatelessWidget {
  const FrameBottomNav({
    required this.activeView,
    required this.onSelectView,
    this.useSafeArea = true,
    super.key,
  });

  final FrameView activeView;
  final ValueChanged<FrameView> onSelectView;

  /// 由应用级壳层托管时壳层已处理底部安全区，无需重复让位。
  final bool useSafeArea;

  static const List<FrameView> _views = <FrameView>[
    FrameView.grid,
    FrameView.timeline,
    FrameView.locations,
    FrameView.tags,
    FrameView.albums,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.frameColors;
    final nav = Container(
      decoration: BoxDecoration(
        color: colors.navBg,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          for (final view in _views)
            Expanded(
              child: _FrameBottomItem(
                key: ValueKey('frame-tab-${view.name}'),
                view: view,
                label: frameViewLabel(l10n, view),
                active: activeView == view,
                onTap: () => onSelectView(view),
              ),
            ),
        ],
      ),
    );
    if (!useSafeArea) {
      return nav;
    }
    return SafeArea(top: false, child: nav);
  }
}

class _FrameBottomItem extends StatelessWidget {
  const _FrameBottomItem({
    required this.view,
    required this.label,
    required this.active,
    required this.onTap,
    super.key,
  });

  final FrameView view;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.frameColors;
    final color = active ? colors.accent : colors.muted;
    return Semantics(
      button: true,
      selected: active,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(frameViewIcon(view), size: 20, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: AppTypography.labelSmall,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
