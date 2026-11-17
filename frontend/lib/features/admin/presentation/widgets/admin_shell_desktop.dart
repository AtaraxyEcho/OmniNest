part of 'admin_shell.dart';

/// 桌面统一壳承载下的管理台：页头 + 分区竖轨 + 分区内容。
///
/// 样例 `Admin.tsx` 用 `set-layout`（页头 + 左侧 `set-nav` + 右侧 `set-body`），
/// 与移动/工位外壳的「56px 顶栏 + 256px 侧栏」不是一套。托管时有桌面
/// 标题栏与侧栏，再画一层就是双顶栏双竖轨；因此这里只保留页面级导航，
/// 顶部品牌/搜索/通知/账户全部交给桌面壳。
class _DesktopAdminShell extends ConsumerWidget {
  const _DesktopAdminShell({
    required this.section,
    required this.onSectionChanged,
    required this.child,
  });

  final AdminSection section;
  final ValueChanged<AdminSection> onSectionChanged;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final permissions =
        ref.watch(authSessionProvider).value?.user?.permissions ??
        const <String>{};
    final user = ref.watch(authSessionProvider).value?.user;
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = (width * 0.03).clamp(
      DesktopMetrics.pageHorizontalMin,
      DesktopMetrics.pageHorizontalMax,
    );
    // 样例 `.set-nav` 是 5 个分区按钮，不再按组展开成 10 行。
    final primary = AdminSection.visiblePrimary(permissions);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 8),
          child: DesktopPageHead(
            eyebrow:
                '${(user?.displayName ?? user?.username ?? '').toUpperCase()}'
                ' · ${l10n.adminConsole.toUpperCase()}',
            title: l10n.adminConsole,
            subtitle: l10n.adminConsoleSubtitle,
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 232,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(horizontal, 6, 14, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                        child: Text(
                          l10n.adminConsole.toUpperCase(),
                          style: DesktopType.eyebrow(skin.text3),
                        ),
                      ),
                      for (final item in primary)
                        _DesktopAdminNavItem(
                          section: item,
                          label: _sectionGroupLabel(l10n, item.group),
                          selected: item.group == section.group,
                          onTap: () => onSectionChanged(item),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  // 右侧内容自带滚动与外边距；这里只补顶部与右缘的呼吸位。
                  padding: EdgeInsets.only(right: horizontal),
                  child: _AdminShellBody(
                    section: section,
                    isWide: true,
                    isUltraWide: width >= 1920,
                    child: child,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesktopAdminNavItem extends StatelessWidget {
  const _DesktopAdminNavItem({
    required this.section,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final AdminSection section;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: DesktopHover(
        builder:
            (context, hovered) => GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: DesktopMotion.of(context, DesktopMotion.fast),
                height: DesktopMetrics.navItemHeightCompact + 3,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color:
                      selected
                          ? skin.accentWash(0.14)
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
                      _iconFor(section),
                      size: DesktopMetrics.iconSmall,
                      color: selected ? skin.accent : skin.text2,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.navItem(
                          selected ? skin.accent : skin.text2,
                        ),
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
