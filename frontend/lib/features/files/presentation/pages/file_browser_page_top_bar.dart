part of 'file_browser_page.dart';

class _FileBackdrop extends StatelessWidget {
  const _FileBackdrop();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: const SizedBox.expand(),
    );
  }
}

/// 56px 工位顶栏：PORTAL 入口、在线徽章、空间联动徽章、32px 搜索槽
/// 与系统级辅助控件（刷新 / 主题 / Aa / 通知 / 头像）。
///
/// 页面级控件（视图切换、上传、详情栏开关）一律下沉工作区工具栏，
/// 严禁出现在全局顶栏。
class _FileTopBar extends ConsumerStatefulWidget {
  const _FileTopBar({required this.state});

  final FileBrowserState state;

  @override
  ConsumerState<_FileTopBar> createState() => _FileTopBarState();
}

class _FileTopBarState extends ConsumerState<_FileTopBar> with RouteTopAware {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final TopBarSearchFocusHandle _searchFocusHandle;

  @override
  void initState() {
    super.initState();
    _searchFocusHandle = TopBarSearchFocusRegistry.instance.register(
      TopBarSearchFocusEntry(
        focus: _searchFocusNode.requestFocus,
        isActive: _isShortcutTarget,
      ),
    );
  }

  /// Ctrl/Cmd+F 目标自检：路由在栈顶且当前分区支持节内搜索。
  bool _isShortcutTarget() {
    if (!isRouteTop) {
      return false;
    }
    return _fileSectionSupportsSearch(widget.state.section);
  }

  @override
  void didUpdateWidget(covariant _FileTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.section != widget.state.section) {
      _searchController.clear();
    } else {
      final query = widget.state.searchQuery;
      if (_searchController.text != query) {
        _searchController.text = query;
      }
    }
  }

  @override
  void dispose() {
    _searchFocusHandle.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final canSearch = _fileSectionSupportsSearch(widget.state.section);
    final isNarrow = MediaQuery.sizeOf(context).width < 720;
    final colors = context.filesColors;
    return WorkbenchTopBar(
      surfaceColor: colors.surface,
      borderColor: colors.outlineVariant,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            WorkstationPortalLink(onTap: () => context.go('/portal')),
            const SizedBox(width: 12),
            Container(width: 1, height: 16, color: colors.outlineVariant),
            const SizedBox(width: 12),
            Text(
              'OmniNest Files / ${widget.state.section.labelOf(l10n)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTypography.titleSmall,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(width: 10),
            const _TopBarOnlineBadge(),
            const SizedBox(width: 8),
            _TopBarSpaceBadge(spaceType: widget.state.spaceType),
            const Spacer(),
            if (canSearch) ...[
              _TopBarSearchSlot(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: controller.setSearchQuery,
                hintText: l10n.filesSearchHint,
                width: isNarrow ? 180.0 : 280.0,
              ),
              const SizedBox(width: 10),
            ],

            if (MediaQuery.of(context).size.width >= 600) ...[
              const SizedBox(width: 8),
              const FontScaleControl(size: 20),
              const SizedBox(width: 8),
              const NotificationIcon(size: 20),
            ],
            const SizedBox(width: 8),
            const UserAvatarMenu(),
          ],
        ),
      ),
    );
  }
}

/// 在线状态徽章：surface-2 底 + 1px 细线 + 实时相位驱动的状态点。
class _TopBarOnlineBadge extends ConsumerWidget {
  const _TopBarOnlineBadge();

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
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.filesColors.surfaceContainer,
        border: Border.all(color: context.filesColors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusDot(color: dotColor, pulsing: pulsing),
          const SizedBox(width: 6),
          Text(
            phase == null || phase == RealtimePhase.signedOut
                ? 'OFFLINE'
                : 'ONLINE',
            style: TextStyle(
              fontFamily: AppTypography.monoFamily,
              fontFamilyFallback: AppTypography.monoFamilyFallback,
              fontSize: AppTypography.labelMicro,
              letterSpacing: 1.5,
              color: context.filesColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 空间联动徽章：随工作区当前空间切换的只读指示。
class _TopBarSpaceBadge extends StatelessWidget {
  const _TopBarSpaceBadge({required this.spaceType});

  final String spaceType;

  @override
  Widget build(BuildContext context) {
    final isShared = spaceType == 'SHARED';
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.filesColors.surfaceContainerLow,
        border: Border.all(color: context.filesColors.outlineVariant),
      ),
      child: Center(
        child: Text(
          isShared
              ? AppLocalizations.of(context).importToSharedSpace
              : AppLocalizations.of(context).importToPersonalSpace,
          style: TextStyle(
            fontFamily: AppTypography.monoFamily,
            fontFamilyFallback: AppTypography.monoFamilyFallback,
            fontSize: AppTypography.labelMicro,
            letterSpacing: 1,
            color: context.filesColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 顶栏 32px 搜索槽：凹入槽体 + 右侧等宽 Ctrl/Cmd+F 快捷键提示。
class _TopBarSearchSlot extends StatelessWidget {
  const _TopBarSearchSlot({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.hintText,
    required this.width,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final String hintText;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    // 快捷键徽标作为输入框内 suffix 呈现，避免悬挂在框外破坏 32px 高度。
    final base = filesWorkstationInputDecoration(context, hintText: hintText);
    return SizedBox(
      width: width,
      height: 32,
      child: ResponsiveSearchField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        hintText: hintText,
        maxWidth: double.infinity,
        decoration: base.copyWith(
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              topBarSearchKeycapLabel,
              style: TextStyle(
                fontFamily: AppTypography.monoFamily,
                fontFamilyFallback: AppTypography.monoFamilyFallback,
                fontSize: AppTypography.labelMicro,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 32,
          ),
          suffixStyle: const TextStyle(),
        ),
      ),
    );
  }
}

const Set<FileManagerSection> _superAdminOnlySections = {
  FileManagerSection.externalStorage,
  FileManagerSection.importTasks,
};

/// 当前 section 是否支持节内搜索。
bool _fileSectionSupportsSearch(FileManagerSection section) =>
    switch (section) {
      FileManagerSection.allFiles ||
      FileManagerSection.recent ||
      FileManagerSection.favorites ||
      FileManagerSection.recycleBin => true,
      _ => false,
    };
