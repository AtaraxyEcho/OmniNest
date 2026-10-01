import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';

/// 工位顶栏 PORTAL 返回链接：返回箭头 + 等宽小写标签，悬停仅精准变色。
///
/// 各模块顶栏统一复用此入口；显式传入 [onTap] 保留模块自己的返回语义，
/// 缺省时从模块内进入则 pop 回来源模块，直达打开时回 Portal。
class WorkstationPortalLink extends StatefulWidget {
  const WorkstationPortalLink({this.onTap, super.key});

  final VoidCallback? onTap;

  @override
  State<WorkstationPortalLink> createState() => _WorkstationPortalLinkState();
}

class _WorkstationPortalLinkState extends State<WorkstationPortalLink> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _hovering ? scheme.onSurface : scheme.onSurfaceVariant;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap:
            widget.onTap ??
            () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/portal');
              }
            },
        child: Semantics(
          button: true,
          label: AppLocalizations.of(context).coreBackToPortal,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_rounded, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  'PORTAL',
                  style: TextStyle(
                    fontFamily: AppTypography.monoFamily,
                    fontFamilyFallback: AppTypography.monoFamilyFallback,
                    fontSize: AppTypography.labelSmall,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
