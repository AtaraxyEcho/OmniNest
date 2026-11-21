import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_backdrop_layer.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_focus_outline.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/features/admin/application/admin_console_access_provider.dart';
import 'package:omninest/features/files/file_dashboard.dart';

/// 一级导航条目：路由、图标、快捷键序号。
@immutable
class DesktopNavItem {
  const DesktopNavItem({
    required this.route,
    required this.icon,
    required this.label,
    required this.shortcut,
  });

  final String route;
  final IconData icon;
  final String label;
  final String shortcut;
}

/// 桌面一级导航（样例 `Shell.tsx` 的 `NAV`）。
///
/// 影视/照片/音乐在移动端已从一级导航退到 Library 之下，桌面按样例恢复
/// 为六个并列空间——侧栏是常驻的，不需要「先进媒体库再进模块」这一跳。
List<DesktopNavItem> desktopNavItems(AppLocalizations l10n) => [
  DesktopNavItem(
    route: DesktopRoutes.home,
    icon: DesktopIcons.home,
    label: l10n.desktopNavHome,
    shortcut: '1',
  ),
  DesktopNavItem(
    route: DesktopRoutes.movies,
    icon: DesktopIcons.film,
    label: l10n.desktopNavMovies,
    shortcut: '2',
  ),
  DesktopNavItem(
    route: DesktopRoutes.photos,
    icon: DesktopIcons.image,
    label: l10n.desktopNavPhotos,
    shortcut: '3',
  ),
  DesktopNavItem(
    route: DesktopRoutes.music,
    icon: DesktopIcons.music,
    label: l10n.desktopNavMusic,
    shortcut: '4',
  ),
  DesktopNavItem(
    route: DesktopRoutes.reader,
    icon: DesktopIcons.book,
    label: l10n.desktopNavReader,
    shortcut: '5',
  ),
  DesktopNavItem(
    route: DesktopRoutes.files,
    icon: DesktopIcons.folder,
    label: l10n.desktopNavFiles,
    shortcut: '6',
  ),
];

/// 判断某条路由是否属于该导航项：模块的二级页仍高亮所属空间。
bool desktopNavIsActive(String path, String route) {
  if (route == '/portal') {
    return path == '/' || path == '/portal';
  }
  return path == route || path.startsWith('$route/');
}

class DesktopSidebar extends ConsumerStatefulWidget {
  const DesktopSidebar({required this.path, super.key});

  final String path;

  @override
  ConsumerState<DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends ConsumerState<DesktopSidebar>
    with SingleTickerProviderStateMixin {
  /// 单一动画控制器统一驱动侧栏所有文字显隐，替代逐项 AnimatedOpacity。
  late final AnimationController _labelController = AnimationController(
    vsync: this,
    duration: MotionToken.fast,
    value: ref.read(desktopShellProvider).sidebarExpanded ? 1 : 0,
  );
  late final CurvedAnimation _labelOpacity = CurvedAnimation(
    parent: _labelController,
    curve: MotionToken.curve,
  );
  bool? _lastExpanded;

  @override
  void dispose() {
    _labelOpacity.dispose();
    _labelController.dispose();
    super.dispose();
  }

  void _syncLabelAnimation(BuildContext context, bool expanded) {
    if (_lastExpanded == expanded) {
      return;
    }
    _lastExpanded = expanded;
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnimations) {
      _labelController.value = expanded ? 1 : 0;
    } else if (expanded) {
      _labelController.forward();
    } else {
      _labelController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final expanded = ref.watch(
      desktopShellProvider.select((s) => s.sidebarExpanded),
    );
    _syncLabelAnimation(context, expanded);
    final backdropActive = desktopBackdropVisibleForRoute(ref, widget.path);
    // 只订阅「紧凑」这一位：整份 watch 会让拖动环境光强度滑杆时每帧重建
    // 整条侧栏（含每个导航项的图标与文字）。
    final compact = ref.watch(
      desktopAppearanceProvider.select((appearance) => appearance.compact),
    );
    final canAdmin = ref.watch(canAccessAdminConsoleProvider);
    final storage = ref.watch(fileStorageStatsProvider).asData?.value;

    final rail = AnimatedContainer(
      duration: DesktopMotion.of(context, DesktopMotion.sidebar),
      curve: DesktopMotion.ease,
      width:
          expanded
              ? DesktopMetrics.sidebarWidth
              : DesktopMetrics.sidebarSlimWidth,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: skin.bg.withValues(alpha: backdropActive ? 0.38 : 0.40),
        border: Border(right: BorderSide(color: skin.line)),
      ),
      // 内容按展开宽度固定排版，收窄时只被裁切：跟样例
      // `.sidebar{overflow:hidden}` 一致。若让标签随宽度回流，
      // 折叠动画的每一帧都会挤出一堆 RenderFlex 溢出。
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        minWidth: _innerWidth,
        maxWidth: _innerWidth,
        child: RepaintBoundary(
          child: SizedBox(
            width: _innerWidth,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 10, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in desktopNavItems(l10n))
                    _SidebarItem(
                      icon: item.icon,
                      label: item.label,
                      shortcut: 'Alt ${item.shortcut}',
                      active: desktopNavIsActive(widget.path, item.route),
                      expanded: expanded,
                      labelOpacity: _labelOpacity,
                      height:
                          compact
                              ? DesktopMetrics.navItemHeightCompact
                              : DesktopMetrics.navItemHeight,
                      onTap: () => desktopGo(context, item.route),
                    ),
                  _SidebarSectionLabel(
                    label: l10n.desktopPinned,
                    expanded: expanded,
                    labelOpacity: _labelOpacity,
                  ),
                  // 样例 `Shell.tsx:160-174`：PINNED 是三条固定演示媒体，
                  // 右侧带数量角标，点击分别进入音乐 / 相册 / 影视。
                  _SidebarItem(
                    icon: DesktopIcons.music,
                    label: l10n.desktopPinnedEveningDrift,
                    count: 42,
                    active: false,
                    expanded: expanded,
                    labelOpacity: _labelOpacity,
                    height: DesktopMetrics.navItemSubHeight,
                    dense: true,
                    onTap: () => desktopGo(context, DesktopRoutes.music),
                  ),
                  _SidebarItem(
                    icon: DesktopIcons.image,
                    label: l10n.desktopPinnedGoldenHour,
                    count: 42,
                    active: false,
                    expanded: expanded,
                    labelOpacity: _labelOpacity,
                    height: DesktopMetrics.navItemSubHeight,
                    dense: true,
                    onTap: () => desktopGo(context, DesktopRoutes.photos),
                  ),
                  _SidebarItem(
                    icon: DesktopIcons.film,
                    label: l10n.desktopPinnedContinue,
                    count: 3,
                    active: false,
                    expanded: expanded,
                    labelOpacity: _labelOpacity,
                    height: DesktopMetrics.navItemSubHeight,
                    dense: true,
                    onTap: () => desktopGo(context, DesktopRoutes.movies),
                  ),
                  const Spacer(),
                  if (canAdmin)
                    _SidebarItem(
                      icon: DesktopIcons.server,
                      label: l10n.desktopNavAdmin,
                      active: desktopNavIsActive(
                        widget.path,
                        DesktopRoutes.admin,
                      ),
                      expanded: expanded,
                      labelOpacity: _labelOpacity,
                      height: DesktopMetrics.navItemHeight,
                      onTap: () => desktopGo(context, DesktopRoutes.admin),
                    ),
                  _SidebarItem(
                    icon: DesktopIcons.settings,
                    label: l10n.desktopNavSettings,
                    shortcut: 'Ctrl ,',
                    active: desktopNavIsActive(
                      widget.path,
                      DesktopRoutes.settings,
                    ),
                    expanded: expanded,
                    labelOpacity: _labelOpacity,
                    height: DesktopMetrics.navItemHeight,
                    onTap: () => desktopGo(context, DesktopRoutes.settings),
                  ),
                  const SizedBox(height: 8),
                  _StorageCard(
                    expanded: expanded,
                    labelOpacity: _labelOpacity,
                    stats: storage,
                  ),
                  const SizedBox(height: DesktopMetrics.playerBarClearance),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return backdropActive
        ? DesktopGlassSurface(
          borderRadius: BorderRadius.zero,
          blur: 26,
          saturation: 1.4,
          child: rail,
        )
        : rail;
  }
}

/// 侧栏内容的固定排版宽度（展开宽度减去左右内边距）。
const double _innerWidth = DesktopMetrics.sidebarWidth - 22;

class _SidebarSectionLabel extends StatelessWidget {
  const _SidebarSectionLabel({
    required this.label,
    required this.expanded,
    required this.labelOpacity,
  });

  final String label;
  final bool expanded;
  final Animation<double> labelOpacity;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return ExcludeSemantics(
      excluding: !expanded,
      child: FadeTransition(
        opacity: labelOpacity,
        alwaysIncludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 18, 0, 6),
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.clip,
            softWrap: false,
            style: DesktopType.eyebrow(skin.text3),
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.expanded,
    required this.labelOpacity,
    required this.height,
    required this.onTap,
    this.shortcut,
    this.count,
    this.dense = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool expanded;
  final Animation<double> labelOpacity;
  final double height;
  final VoidCallback onTap;
  final String? shortcut;

  /// 样例侧栏 PINNED 条目右侧的演示数量角标（`<em>{n}</em>`）。
  final int? count;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    // 样例侧栏条目是 `<button class="nav-item">`：Tab 可达、Enter/Space 可激活。
    // 自绘的 GestureDetector 不会进 Tab 顺序，必须补焦点外壳与按钮语义，
    // 否则「管理台 / 设置」在键盘下只能绕道（命令面板按样例已不再收录它们）。
    final tooltipMessage =
        shortcut != null
            ? '$label ($shortcut)'
            : count != null
            ? '$label ($count)'
            : label;
    final item = Semantics(
      button: true,
      selected: active,
      // 折叠态下文字被 ExcludeSemantics 屏蔽，外显 label 是唯一来源；
      // 展开态若同时保留子节点语义会被播报两次（"Admin\nAdmin"），
      // 因此整行语义由这里独占，计数折进 label 一并播报。
      label: count == null ? label : '$label · $count',
      excludeSemantics: true,
      child: DesktopFocusOutline(
        radius: DesktopMetrics.radiusButton,
        onActivate: onTap,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: DesktopHover(
            builder:
                (context, hovered) => GestureDetector(
                  onTap: onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: height,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color:
                          active
                              ? skin.raise2
                              : hovered
                              ? skin.raise
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        DesktopMetrics.radiusButton,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          icon,
                          size: dense ? 16 : DesktopMetrics.iconMedium,
                          color:
                              active
                                  ? skin.accent
                                  : hovered
                                  ? skin.text
                                  : skin.text2,
                        ),
                        Expanded(
                          child: ExcludeSemantics(
                            excluding: !expanded,
                            child: FadeTransition(
                              opacity: labelOpacity,
                              alwaysIncludeSemantics: true,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        label,
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.fade,
                                        style:
                                            dense
                                                ? DesktopType.navSub(
                                                  active || hovered
                                                      ? skin.text
                                                      : skin.text2,
                                                )
                                                : DesktopType.navItem(
                                                  active || hovered
                                                      ? skin.text
                                                      : skin.text2,
                                                ),
                                      ),
                                    ),
                                    if (shortcut != null) ...[
                                      const SizedBox(width: 8),
                                      Opacity(
                                        opacity: hovered ? 0.8 : 0,
                                        child: Text(
                                          shortcut!,
                                          style: DesktopType.nano(skin.text3),
                                        ),
                                      ),
                                    ],
                                    if (count != null) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        '$count',
                                        style: DesktopType.nano(skin.text3),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
    if (!expanded) {
      return Tooltip(
        message: tooltipMessage,
        waitDuration: const Duration(milliseconds: 300),
        child: item,
      );
    }
    return item;
  }
}

class _StorageCard extends StatelessWidget {
  const _StorageCard({
    required this.expanded,
    required this.labelOpacity,
    required this.stats,
  });

  final bool expanded;
  final Animation<double> labelOpacity;
  final FileStorageStats? stats;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final used = stats == null ? '—' : formatFileSize(stats!.usedBytes);
    final unlimited = stats?.isQuotaUnlimited ?? true;
    final total =
        stats == null || unlimited ? null : formatFileSize(stats!.quotaBytes);
    final ratio = stats == null || unlimited ? 0.0 : stats!.usageRatio;
    final caption =
        stats == null
            ? '—'
            : unlimited
            ? l10n.desktopStorageUnlimited(used)
            : l10n.desktopStorageUsage(used, total!);

    final card = DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            onTap: () => desktopGo(context, DesktopRoutes.filesStorage),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hovered ? skin.raise2 : skin.raise,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: skin.line),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: CustomPaint(
                      painter: _RingPainter(
                        fraction: ratio,
                        track: skin.raise3,
                        value: skin.accent,
                      ),
                      child: Center(
                        child: Text(
                          unlimited ? '∞' : '${(ratio * 100).round()}%',
                          style: DesktopType.nano(skin.text).copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: unlimited ? 13 : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ExcludeSemantics(
                      excluding: !expanded,
                      child: FadeTransition(
                        opacity: labelOpacity,
                        alwaysIncludeSemantics: true,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                // 样例 `Shell.tsx:180` 的服务器名。
                                'OmniCloud',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.fade,
                                style: DesktopType.denseStrong(skin.text),
                              ),
                              Text(
                                caption,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.fade,
                                style: DesktopType.micro(skin.text3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
    if (!expanded) {
      return Tooltip(
        message: 'OmniCloud · $caption',
        waitDuration: const Duration(milliseconds: 300),
        child: card,
      );
    }
    return card;
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.track,
    required this.value,
  });

  final double fraction;
  final Color track;
  final Color value;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final base =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (fraction <= 0) {
      return;
    }
    final progress =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..color = value;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * fraction.clamp(0.0, 1.0),
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.track != track ||
      oldDelegate.value != value;
}
