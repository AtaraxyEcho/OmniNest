part of 'file_browser_page.dart';

/// 桌面工位侧栏：256px、根画板底色、右侧 1px 细线。
///
/// 结构自上而下：品牌卡（状态点 + 等宽副标）→ 个人/共享空间直角分段
/// 切换器 → 分组导航（上方 flex-1 滚动）→ 底部固定存储微卡（shrink-0）。
class _FileSidebar extends ConsumerWidget {
  const _FileSidebar({
    required this.state,
    required this.enabled,
    required this.onSectionChanged,
  });

  final FileBrowserState state;
  final bool enabled;
  final ValueChanged<FileManagerSection> onSectionChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(authSessionProvider).asData?.value.user;
    final canManageExternalStorage =
        user?.permissions.contains('system:config:manage') ?? false;
    return Container(
      width: AppControlTokens.sidebarWidth,
      decoration: BoxDecoration(
        color: context.filesColors.surface,
        border: Border(
          right: BorderSide(color: context.filesColors.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SideHeader(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: _SpaceSegmented(
              currentSpaceType: state.spaceType,
              enabled: enabled,
              onChanged: (value) {
                if (value != state.spaceType) {
                  unawaited(
                    _runFileAction(
                      context,
                      () => ref
                          .read(fileBrowserControllerProvider.notifier)
                          .switchSpace(value),
                    ),
                  );
                }
              },
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                for (final entry in _fileSidebarGroups.entries) ...[
                  _FileSidebarGroupLabel(
                    label: entry.key.labelOf(l10n),
                    code: switch (entry.key) {
                      _FileSidebarGroup.files => 'FILES',
                      _FileSidebarGroup.sharing => 'SHARED',
                      _FileSidebarGroup.transfer => 'TRANSFERS',
                      _FileSidebarGroup.storage => 'STORAGE',
                    },
                  ),
                  const SizedBox(height: 6),
                  for (final section in entry.value)
                    if (canManageExternalStorage ||
                        !_superAdminOnlySections.contains(section))
                      _FileNavItem(
                        section: section,
                        selected: state.section == section,
                        enabled: enabled,
                        onTap: () => onSectionChanged(section),
                      ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
          _StorageMiniCard(stats: state.storageStats),
        ],
      ),
    );
  }
}

class _SideHeader extends ConsumerWidget {
  const _SideHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(realtimePhaseProvider).asData?.value;
    final (dotColor, pulsing) = switch (phase) {
      RealtimePhase.healthy ||
      RealtimePhase.subscribed ||
      RealtimePhase.catchingUp => (context.filesColors.success, true),
      RealtimePhase.connecting ||
      RealtimePhase.reconnecting => (context.filesColors.warning, false),
      RealtimePhase.degraded => (context.filesColors.error, false),
      RealtimePhase.signedOut ||
      null => (context.filesColors.onSurfaceVariant, false),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.filesColors.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          const BrandLogo.sidebar(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'OmniNest Files',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _StatusDot(color: dotColor, pulsing: pulsing),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'FILE MANAGER',
                  style: TextStyle(
                    fontFamily: AppTypography.monoFamily,
                    fontFamilyFallback: AppTypography.monoFamilyFallback,
                    fontSize: AppTypography.labelMicro,
                    letterSpacing: 2,
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

/// 状态指示灯：唯一允许正圆的元素，1.5px 级别小点。
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color, this.pulsing = false});

  final Color color;
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (!pulsing) {
      return dot;
    }
    return _PulsingStatusDot(child: dot);
  }
}

class _PulsingStatusDot extends StatefulWidget {
  const _PulsingStatusDot({required this.child});

  final Widget child;

  @override
  State<_PulsingStatusDot> createState() => _PulsingStatusDotState();
}

class _PulsingStatusDotState extends State<_PulsingStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: MotionToken.stagger,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(
        begin: 0.35,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

class _FileSidebarGroupLabel extends StatelessWidget {
  const _FileSidebarGroupLabel({required this.label, required this.code});

  final String label;
  final String code;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
      child: Text.rich(
        TextSpan(
          text: label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: AppTypography.bodySmall,
            height: 18 / AppTypography.bodySmall,
            color: context.filesColors.sidebarOnSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
          children: [TextSpan(text: ' ($code)')],
        ),
      ),
    );
  }
}

/// 侧栏导航项：纯平直角，激活态靠背景与 1px 边框表达，禁左侧线段。
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
        selected || _hovering
            ? context.filesColors.sidebarSelectedFg
            : context.filesColors.sidebarOnSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
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
            duration: MotionToken.fast,
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color:
                  selected
                      ? context.filesColors.sidebarSelectedBg
                      : _hovering
                      ? context.filesColors.sidebarHoverBg
                      : Colors.transparent,
              border: Border.all(
                color:
                    selected
                        ? context.filesColors.sidebarSelectedBorder
                        : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(widget.section.icon, size: 16, color: foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.section.labelOf(AppLocalizations.of(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTypography.bodyMedium,
                      height: 18 / AppTypography.bodyMedium,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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

/// 个人/共享空间直角分段切换器。
///
/// 两按钮 Expanded 绝对等宽；1px 边框常驻（未激活透明），激活纯靠
/// 变色驱动，杜绝尺寸跳变。切换空间不自动展开任何抽屉。
class _SpaceSegmented extends StatelessWidget {
  const _SpaceSegmented({
    required this.currentSpaceType,
    required this.enabled,
    required this.onChanged,
  });

  final String currentSpaceType;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isShared = currentSpaceType == 'SHARED';
    return Row(
      children: [
        Expanded(
          child: _SpaceSegmentButton(
            icon: Icons.lock_outline,
            label: l10n.importToPersonalSpace,
            selected: !isShared,
            enabled: enabled,
            onTap: () => onChanged('PERSONAL'),
          ),
        ),
        Expanded(
          child: _SpaceSegmentButton(
            icon: Icons.group_outlined,
            label: l10n.importToSharedSpace,
            selected: isShared,
            enabled: enabled,
            onTap: () => onChanged('SHARED'),
          ),
        ),
      ],
    );
  }
}

class _SpaceSegmentButton extends StatefulWidget {
  const _SpaceSegmentButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_SpaceSegmentButton> createState() => _SpaceSegmentButtonState();
}

class _SpaceSegmentButtonState extends State<_SpaceSegmentButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    final selected = widget.selected;
    final foreground =
        selected
            ? colors.sidebarSelectedFg
            : _hovering && widget.enabled
            ? colors.onSurface
            : colors.sidebarOnSurfaceVariant;
    return MouseRegion(
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: MotionToken.fast,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colors.sidebarSelectedBg : Colors.transparent,
            border: Border.all(
              color: selected ? colors.outlineVariant : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: foreground),
              const SizedBox(width: 6),
              // 英文等长文案下 Text 固有宽会超出侧栏宽度；必须用
              // Flexible 让 ellipsis 在有界约束内生效，否则整行溢出。
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTypography.bodySmall,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部固定存储微卡：吸附侧栏最底部，配额数值 + 1px 进度槽 + 等宽百分比。
class _StorageMiniCard extends StatelessWidget {
  const _StorageMiniCard({required this.stats});

  final FileStorageStats? stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.filesColors;
    final value = stats?.usageRatio ?? 0;
    final percent =
        stats == null || stats!.isQuotaUnlimited ? null : (value * 100).round();
    final quotaText =
        stats == null
            ? '---'
            : stats!.isQuotaUnlimited
            ? '${formatFileSize(stats!.usedBytes)} / ${l10n.filesUnlimited}'
            : '${formatFileSize(stats!.usedBytes)} / ${formatFileSize(stats!.quotaBytes)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.filesStorageUsage,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                quotaText,
                style: TextStyle(
                  fontFamily: AppTypography.monoFamily,
                  fontFamilyFallback: AppTypography.monoFamilyFallback,
                  fontSize: AppTypography.labelSmall,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRect(
            child: SizedBox(
              height: 1,
              child: LinearProgressIndicator(
                value: value,
                minHeight: 1,
                color: colors.storageAccent,
                backgroundColor: colors.outlineVariant,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              percent == null ? '—' : '$percent%',
              style: TextStyle(
                fontFamily: AppTypography.monoFamily,
                fontFamilyFallback: AppTypography.monoFamilyFallback,
                fontSize: AppTypography.labelSmall,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 带 fade 过渡的 section 包装器：侧栏切换联动主区微淡入（160ms）。
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
    if (!virtualizedWorkspace) {
      // 子页（共享/传输/存储）使用 Column>Expanded 布局，需要稳定有界
      // 约束；AnimatedSwitcher 的 Stack 在过渡期间引入无界旧子树会触发
      // RenderAnimatedOpacity/parentDataDirty/Tooltip 多 Ticker 三联断言，
      // 因此非虚拟化分区直接返回 child 不做过渡。
      return child;
    }
    return AnimatedSwitcher(
      duration: MotionToken.resolve(context, MotionToken.pageSwitch),
      switchInCurve: MotionToken.curve,
      switchOutCurve: MotionToken.curveIn,
      // 退场子树排除语义，避免与入场子树同批更新触发 Windows 桥失败。
      layoutBuilder: excludeExitingSemanticsStack,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: child,
    );
  }
}
