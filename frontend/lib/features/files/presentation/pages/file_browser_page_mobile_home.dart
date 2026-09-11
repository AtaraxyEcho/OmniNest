part of 'file_browser_page.dart';

/// 文件模块移动首页（Google Files 式）：
/// 位置（个人/共享空间）双卡 + 分区卡网格 + 「更多」底部面板。
///
/// 点分区卡进入列表态（面包屑与列表仅在列表态出现），返回经
/// [_FileMobileBackRow] 或系统返回手势回到首页。
class _FileMobileHome extends ConsumerWidget {
  const _FileMobileHome({required this.state, required this.onOpenSection});

  final FileBrowserState state;

  /// 打开分区：进入列表态。
  final ValueChanged<FileManagerSection> onOpenSection;

  static const List<FileManagerSection> _cardSections = [
    FileManagerSection.allFiles,
    FileManagerSection.recent,
    FileManagerSection.favorites,
    FileManagerSection.recycleBin,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 108),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HomeGroupLabel(l10n.filesHomeLocations),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _HomeSpaceCard(
                  icon: Icons.lock_outline,
                  label: l10n.importToPersonalSpace,
                  hint: l10n.filesHomePersonalSpaceHint,
                  selected: state.spaceType != 'SHARED',
                  onTap: () => _switchSpace(context, controller, 'PERSONAL'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HomeSpaceCard(
                  icon: Icons.people_outline,
                  label: l10n.filesSharedSpace,
                  hint: l10n.filesSharedSpaceDesc,
                  selected: state.spaceType == 'SHARED',
                  onTap: () => _switchSpace(context, controller, 'SHARED'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          _HomeGroupLabel(l10n.filesHomeSections),
          const SizedBox(height: 10),
          for (var row = 0; row < _cardSections.length; row += 2) ...[
            Row(
              children: [
                Expanded(
                  child: _HomeSectionCard(
                    section: _cardSections[row],
                    hint: _hintOf(l10n, _cardSections[row]),
                    onTap: () => onOpenSection(_cardSections[row]),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child:
                      row + 1 < _cardSections.length
                          ? _HomeSectionCard(
                            section: _cardSections[row + 1],
                            hint: _hintOf(l10n, _cardSections[row + 1]),
                            onTap: () => onOpenSection(_cardSections[row + 1]),
                          )
                          : const SizedBox.shrink(),
                ),
              ],
            ),
            if (row + 2 < _cardSections.length + 1) const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          _HomeSectionCard(
            section: null,
            icon: Icons.grid_view_rounded,
            label: l10n.filesMoreSections,
            hint: l10n.filesHomeMoreHint,
            onTap: () => showFileMoreSectionsSheet(context, ref, onOpenSection),
          ),
        ],
      ),
    );
  }

  String _hintOf(AppLocalizations l10n, FileManagerSection section) {
    return switch (section) {
      FileManagerSection.allFiles => l10n.filesHomeAllFilesHint,
      FileManagerSection.recent => l10n.filesHomeRecentHint,
      FileManagerSection.favorites => l10n.filesHomeFavoritesHint,
      FileManagerSection.recycleBin => l10n.filesHomeTrashHint,
      _ => section.descriptionOf(l10n),
    };
  }

  void _switchSpace(
    BuildContext context,
    FileBrowserController controller,
    String spaceType,
  ) {
    if (spaceType == state.spaceType) {
      return;
    }
    unawaited(_runFileAction(context, () => controller.switchSpace(spaceType)));
  }
}

/// 首页分组小标题。
class _HomeGroupLabel extends StatelessWidget {
  const _HomeGroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.filesColors.onSurfaceVariant,
        fontSize: AppTypography.labelLarge,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// 位置卡：个人/共享空间切换，选中态以主色图标与淡底强调。
class _HomeSpaceCard extends StatelessWidget {
  const _HomeSpaceCard({
    required this.icon,
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.filesColors;
    return Material(
      color: selected ? c.primaryContainer.withValues(alpha: 0.55) : c.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? c.primary : c.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.onSurface,
                        fontSize: AppTypography.bodyLarge,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.onSurfaceVariant,
                        fontSize: AppTypography.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, size: 18, color: c.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分区卡：图标 + 标题 + 一行说明；点击进入列表态。
class _HomeSectionCard extends StatelessWidget {
  const _HomeSectionCard({
    required this.section,
    required this.hint,
    required this.onTap,
    this.icon,
    this.label,
  });

  final FileManagerSection? section;

  /// 自定义图标/标题（「更多」卡无对应分区）。
  final IconData? icon;
  final String? label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.filesColors;
    final l10n = AppLocalizations.of(context);
    final title = label ?? section!.labelOf(l10n);
    final glyph = icon ?? section!.icon;
    return Material(
      color: c.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(glyph, size: 26, color: c.primary),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.onSurface,
                  fontSize: AppTypography.bodyLarge,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.onSurfaceVariant,
                  fontSize: AppTypography.labelSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 列表态顶部返回行：回到文件首页。
class _FileMobileBackRow extends StatelessWidget {
  const _FileMobileBackRow({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back_rounded, size: 18),
        label: Text(AppLocalizations.of(context).coreBack),
        style: TextButton.styleFrom(
          foregroundColor: context.filesColors.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

/// 其余分区（共享/传输/存储）底部面板；超管分区按权限过滤。
///
/// 原属 [_FileMobileSectionBar]，分区条移除后供首页「更多」卡复用。
void showFileMoreSectionsSheet(
  BuildContext context,
  WidgetRef ref,
  ValueChanged<FileManagerSection> onOpen,
) {
  final l10n = AppLocalizations.of(context);
  final user = ref.read(authSessionProvider).asData?.value.user;
  final canManageSystemConfig =
      user?.permissions.contains('system:config:manage') ?? false;
  const primarySections = <FileManagerSection>[
    FileManagerSection.allFiles,
    FileManagerSection.recent,
    FileManagerSection.favorites,
    FileManagerSection.sharedWithMe,
    FileManagerSection.recycleBin,
  ];
  final groups = <_FileSidebarGroup, List<FileManagerSection>>{
    for (final entry in _fileSidebarGroups.entries)
      entry.key: [
        for (final item in entry.value)
          if (!primarySections.contains(item) &&
              (canManageSystemConfig ||
                  !_superAdminOnlySections.contains(item)))
            item,
      ],
  }..removeWhere((_, value) => value.isEmpty);

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder:
        (sheetContext) => SafeArea(
          top: false,
          // 小屏/大字号下分组列表可能超出 sheet 可用高，滚动兜底。
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
                    child: Text(
                      entry.key.labelOf(l10n),
                      style: TextStyle(
                        fontSize: AppTypography.labelMedium,
                        fontWeight: FontWeight.w700,
                        color: context.filesColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final item in entry.value)
                    ListTile(
                      leading: Icon(item.icon),
                      title: Text(item.labelOf(l10n)),
                      dense: true,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        onOpen(item);
                      },
                    ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
  );
}
