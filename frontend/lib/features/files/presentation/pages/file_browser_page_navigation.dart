part of 'file_browser_page.dart';

class _FileSidebar extends ConsumerWidget {
  const _FileSidebar({
    required this.state,
    required this.enabled,
    required this.closeOnSelect,
    required this.onSectionChanged,
  });

  final FileBrowserState state;
  final bool enabled;
  final bool closeOnSelect;
  final ValueChanged<FileManagerSection> onSectionChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(authSessionProvider).asData?.value.user;
    final canManageExternalStorage =
        user?.permissions.contains('system:config:manage') ?? false;
    return Container(
      width: AppControlTokens.sidebarWidth,
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
      decoration: BoxDecoration(
        color: context.filesColors.surfaceContainerLow.withValues(alpha: 0.9),
        border: Border(
          right: BorderSide(
            color: context.filesColors.outlineVariant.withValues(alpha: 0.18),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SideHeader(),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              children: [
                for (final entry in _fileSidebarGroups.entries) ...[
                  _FileSidebarGroupLabel(label: entry.key.labelOf(l10n)),
                  const SizedBox(height: 8),
                  for (final section in entry.value)
                    if (canManageExternalStorage ||
                        !_superAdminOnlySections.contains(section))
                      _FileNavItem(
                        section: section,
                        selected: state.section == section,
                        enabled: enabled,
                        onTap: () {
                          if (closeOnSelect) {
                            Navigator.of(context).pop();
                          }
                          onSectionChanged(section);
                        },
                      ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _StorageMiniCard(stats: state.storageStats),
        ],
      ),
    );
  }
}

class _SideHeader extends StatelessWidget {
  const _SideHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          const BrandLogo.sidebar(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OmniNest Files',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  'File Manager',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.filesColors.sidebarOnSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FileSidebarGroupLabel extends StatelessWidget {
  const _FileSidebarGroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: AppTypography.bodySmall,
          height: 18 / 12,
          color: context.filesColors.sidebarOnSurfaceVariant,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _FileNavItem extends StatefulWidget {
  const _FileNavItem({
    required this.section,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final FileManagerSection section;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_FileNavItem> createState() => _FileNavItemState();
}

class _FileNavItemState extends State<_FileNavItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final foreground =
        selected
            ? context.filesColors.sidebarSelectedFg
            : context.filesColors.sidebarOnSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        cursor:
            widget.enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: widget.enabled ? widget.onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 40,
            decoration: BoxDecoration(
              color:
                  selected
                      ? context.filesColors.sidebarSelectedBg
                      : _hovering
                      ? context.filesColors.sidebarHoverBg
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color:
                    selected
                        ? context.filesColors.sidebarSelectedBorder
                        : _hovering
                        ? Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.36)
                        : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(widget.section.icon, size: 18, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.section.labelOf(AppLocalizations.of(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTypography.bodyMedium,
                      height: 18 / 13,
                      fontWeight: FontWeight.w600,
                      color: foreground,
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

class _StorageMiniCard extends StatelessWidget {
  const _StorageMiniCard({required this.stats});

  final FileStorageStats? stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = stats?.usageRatio ?? 0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.filesStorageUsage,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: value, minHeight: 6),
            const SizedBox(height: 10),
            Text(
              stats == null
                  ? l10n.filesWaitingStats
                  : stats!.isQuotaUnlimited
                  ? l10n.filesUsedOf(
                    l10n.filesUnlimited,
                    formatFileSize(stats!.usedBytes),
                  )
                  : l10n.filesUsedOf(
                    formatFileSize(stats!.quotaBytes),
                    formatFileSize(stats!.usedBytes),
                  ),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: context.filesColors.sidebarOnSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 带 fade+slide 过渡动画的 section 包装器。
class _AnimatedSectionBody extends StatelessWidget {
  const _AnimatedSectionBody({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context) {
    final child = _FileSectionBody(key: ValueKey(state.section), state: state);
    // 文件节点工作区自带滚动主体，其它分区需要外层滚动。
    final virtualizedWorkspace = switch (state.section) {
      FileManagerSection.allFiles ||
      FileManagerSection.sharedSpace ||
      FileManagerSection.recent ||
      FileManagerSection.favorites ||
      FileManagerSection.recycleBin ||
      FileManagerSection.storageStats => true,
      _ => false,
    };
    return AnimatedSwitcher(
      duration: MotionToken.normal,
      switchInCurve: MotionToken.curve,
      switchOutCurve: MotionToken.curveIn,
      // 退场子树排除语义，避免与入场子树同批更新触发 Windows 桥失败。
      layoutBuilder: excludeExitingSemanticsStack,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: MotionToken.curve,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: MotionToken.slideContent,
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child:
          virtualizedWorkspace
              ? child
              : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: child,
              ),
    );
  }
}
