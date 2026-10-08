part of 'file_browser_page.dart';

/// 文件空间首页：存储条 + 分类格 + 页签工具栏 + 内联根列表（原型 Files）。
///
/// 页签在「我的文件 / 共享」两个空间根之间原地切换；工具栏含视图
/// 切换、新建与更多分区；内联列表直接操作当前空间根（目录原地展开，
/// 点文件开预览），进入目录后收起首页卡片仅留工具栏与返回上级栏，
/// 超过预览条数经「查看全部」进入完整工作区（仅根态提供）。
class _FileMobileHome extends ConsumerWidget {
  const _FileMobileHome({
    required this.state,
    required this.onOpenSection,
    required this.onEnterWorkspace,
  });

  final FileBrowserState state;

  /// 打开分区：进入列表态。
  final ValueChanged<FileManagerSection> onOpenSection;

  /// 从内联列表进入工作区（不重载分区）。
  final VoidCallback onEnterWorkspace;

  static const int _inlinePreviewLimit = 12;

  static const List<FileManagerSection> _cardSections = [
    FileManagerSection.recent,
    FileManagerSection.favorites,
    FileManagerSection.sharedWithMe,
    FileManagerSection.offlineDownloads,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    // 目录原地展开态：内联列表已进入某目录（面包屑非空）。此态收起
    // 存储条与分类格，仅保留工具栏 + 返回上级栏 + 全量目录内容，
    // 语义对齐主流网盘（同视图内导航，不切换页面 chrome）。
    final inFolder =
        state.section == FileManagerSection.allFiles &&
        state.breadcrumbs.isNotEmpty;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0 ||
            notification.metrics.axis != Axis.vertical ||
            notification.metrics.extentAfter >= 420 ||
            state.isBusy ||
            state.filePage + 1 >= state.fileTotalPages) {
          return false;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(controller.loadMoreFiles());
        });
        return false;
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!inFolder) ...[
              _HomeStorageStrip(
                stats: state.storageStats,
                onTap: () => onOpenSection(FileManagerSection.storageStats),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  for (
                    var index = 0;
                    index < _cardSections.length;
                    index++
                  ) ...[
                    if (index > 0) const SizedBox(width: 7),
                    Expanded(
                      child: _HomeSectionCard(
                        section: _cardSections[index],
                        hint: _hintOfCard(context, _cardSections[index]),
                        onTap: () => onOpenSection(_cardSections[index]),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
            ] else ...[
              _InlineGoUpBar(state: state, controller: controller),
              const SizedBox(height: 4),
            ],
            _HomeToolbar(
              state: state,
              controller: controller,
              onOpenSection: onOpenSection,
              onEnterWorkspace: onEnterWorkspace,
            ),
            const SizedBox(height: 8),
            _HomeInlineList(
              state: state,
              controller: controller,
              onEnterWorkspace: onEnterWorkspace,
              onOpenSection: onOpenSection,
            ),
            if (!inFolder) ...[
              _HomeToolsLabel(label: l10n.filesHomeWorkspaceTools),
              _HomeToolShortcuts(state: state, onOpenSection: onOpenSection),
            ],
          ],
        ),
      ),
    );
  }

  String _hintOfCard(BuildContext context, FileManagerSection section) {
    final l10n = AppLocalizations.of(context);
    return switch (section) {
      FileManagerSection.recent => l10n.filesHomeRecentHint,
      FileManagerSection.favorites => l10n.filesHomeFavoritesHint,
      FileManagerSection.sharedWithMe => l10n.filesSharedWithMeDesc,
      _ => l10n.filesOfflineDownloadsDesc,
    };
  }
}

/// 页签工具栏：空间页签（下划线激活）+ 视图切换 + 新建 + 更多。
class _HomeToolbar extends StatelessWidget {
  const _HomeToolbar({
    required this.state,
    required this.controller,
    required this.onOpenSection,
    required this.onEnterWorkspace,
  });

  final FileBrowserState state;
  final FileBrowserController controller;
  final ValueChanged<FileManagerSection> onOpenSection;
  final VoidCallback onEnterWorkspace;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shared = state.spaceType == 'SHARED';
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.env.line07)),
      ),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            _HomeToolbarTab(
              label: l10n.filesHomeTabMyFiles,
              active: !shared,
              onTap: () => _switchSpace(context, 'PERSONAL'),
            ),
            _HomeToolbarTab(
              label: l10n.filesSharedSpace,
              active: shared,
              onTap: () => _switchSpace(context, 'SHARED'),
            ),
            const Spacer(),
            _ToolbarIconButton(
              tooltip: l10n.filesViewList,
              icon: OmniIcons.list,
              active: state.viewMode == FileBrowserViewMode.list,
              onTap: () => controller.setViewMode(FileBrowserViewMode.list),
            ),
            _ToolbarIconButton(
              tooltip: l10n.filesViewGrid,
              icon: OmniIcons.grid,
              active: state.viewMode == FileBrowserViewMode.grid,
              onTap: () => controller.setViewMode(FileBrowserViewMode.grid),
            ),
            _ToolbarIconButton(
              tooltip: l10n.portalQuickUpload,
              icon: OmniIcons.plus,
              onTap: () => _showFileCreateActions(context, state, controller),
            ),
            _ToolbarMoreButton(
              onOpenSection: onOpenSection,
              onEnterWorkspace: onEnterWorkspace,
            ),
          ],
        ),
      ),
    );
  }

  void _switchSpace(BuildContext context, String spaceType) {
    if (spaceType == state.spaceType) {
      return;
    }
    // 空间原地切换：内联列表内容随之更换，不离开首页 chrome。
    unawaited(_runFileAction(context, () => controller.switchSpace(spaceType)));
  }
}

/// 空间页签：激活态墨色 + 2px 强调色下划线。
class _HomeToolbarTab extends StatelessWidget {
  const _HomeToolbarTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: active ? context.env.ink : context.env.inkMuted,
                    fontSize: AppTypography.bodySmall,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 190),
              width: active ? 28 : 0,
              height: 2,
              color: active ? context.env.accentInk : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}

/// 工具栏图标钮：激活态强调色前景。
class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String tooltip;
  final OmniIconsData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: OmniIcon(
        icon: icon,
        size: 19,
        color: active ? context.env.accentInk : context.env.inkMuted,
      ),
      style: IconButton.styleFrom(
        foregroundColor: active ? context.env.accentInk : context.env.inkMuted,
        minimumSize: const Size.square(43),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// 更多分区钮：打开回收站/上传队列/离线等低频分区面板。
class _ToolbarMoreButton extends ConsumerWidget {
  const _ToolbarMoreButton({
    required this.onOpenSection,
    required this.onEnterWorkspace,
  });

  final ValueChanged<FileManagerSection> onOpenSection;
  final VoidCallback onEnterWorkspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      tooltip: l10n.filesMoreSections,
      onPressed: () => showFileMoreSectionsSheet(context, ref, onOpenSection),
      icon: OmniIcon(
        icon: OmniIcons.more,
        size: 19,
        color: context.env.inkMuted,
      ),
      style: IconButton.styleFrom(
        foregroundColor: context.env.inkMuted,
        minimumSize: const Size.square(43),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// 内联根列表：按当前视图模式渲染前若干条；进文件夹入工作区、点文件预览。
class _HomeInlineList extends StatelessWidget {
  const _HomeInlineList({
    required this.state,
    required this.controller,
    required this.onEnterWorkspace,
    required this.onOpenSection,
  });

  final FileBrowserState state;
  final FileBrowserController controller;
  final VoidCallback onEnterWorkspace;
  final ValueChanged<FileManagerSection> onOpenSection;

  @override
  Widget build(BuildContext context) {
    final files = state.files;
    final l10n = AppLocalizations.of(context);
    if (files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OmniIcon(
              icon: OmniIcons.folder,
              size: 22,
              color: context.env.white46,
            ),
            const SizedBox(width: 10),
            Text(
              l10n.filesEmpty,
              style: TextStyle(
                color: context.env.inkMuted,
                fontSize: AppTypography.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }
    // 目录原地展开态：不再截断预览条数（续载由外层滚动监听负责），
    // 也不渲染「查看全部」。
    final inFolder =
        state.section == FileManagerSection.allFiles &&
        state.breadcrumbs.isNotEmpty;
    final visible =
        inFolder
            ? files.toList(growable: false)
            : files.take(_FileMobileHome._inlinePreviewLimit).toList();
    final Widget content;
    if (state.viewMode == FileBrowserViewMode.grid) {
      // 高度按实际列宽精确换算（宽/1.62 为瓦片高），避免固定 112 的
      // 累计误差造成底部裁切或溢出。
      content = LayoutBuilder(
        builder: (context, constraints) {
          final tileWidth = (constraints.maxWidth - 9) / 2;
          final tileHeight = tileWidth / 1.62;
          final rows = (visible.length / 2).ceil();
          return SizedBox(
            height: rows * tileHeight + (rows - 1) * 9.0,
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 9,
              crossAxisSpacing: 9,
              childAspectRatio: 1.62,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final file in visible)
                  FileEnvTile(
                    file: file,
                    selected: false,
                    favorite: state.favoriteIdSet.contains(file.id),
                    onTap: () => _activate(context, file),
                  ),
              ],
            ),
          );
        },
      );
    } else {
      content = Column(
        children: [
          for (var index = 0; index < visible.length; index++) ...[
            FileEnvRow(
              file: visible[index],
              selected: false,
              onTap: () => _activate(context, visible[index]),
            ),
            if (index + 1 < visible.length)
              Divider(height: 1, color: context.env.line07),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        content,
        if (!inFolder && files.length > _FileMobileHome._inlinePreviewLimit)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextButton(
              onPressed: () => onOpenSection(FileManagerSection.allFiles),
              style: TextButton.styleFrom(
                foregroundColor: context.env.white70,
                minimumSize: const Size(48, 44),
              ),
              child: Text(l10n.portalMobileViewAll),
            ),
          ),
      ],
    );
  }

  void _activate(BuildContext context, FileNode file) {
    if (file.isFolder) {
      // 主流网盘语义：目录在当前视图内原地展开，不切换页面 chrome。
      unawaited(controller.openFolder(file));
      return;
    }
    _openFilePreview(context, file);
  }
}

/// 存储条：配额用量 + 3px 进度，点击进入存储统计分区。
class _HomeStorageStrip extends StatelessWidget {
  const _HomeStorageStrip({required this.stats, required this.onTap});

  final FileStorageStats? stats;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.filesColors;
    final l10n = AppLocalizations.of(context);
    final value = stats;
    final line =
        value == null
            ? l10n.filesWaitingStats
            : l10n.filesStorageQuotaLine(
              formatFileSize(value.usedBytes),
              formatFileSize(value.quotaBytes),
            );
    return Material(
      color: c.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: c.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.storageAccent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.zero,
                ),
                child: OmniIcon(
                  icon: OmniIcons.cloud,
                  size: 21,
                  color: context.env.storageCloud,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.filesStorageUsage,
                      style: TextStyle(
                        color: c.onSurface,
                        fontSize: AppTypography.bodyLarge,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.onSurfaceVariant,
                        fontSize: AppTypography.labelSmall,
                      ),
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: value == null ? 0 : value.usageRatio.clamp(0, 1),
                        minHeight: 3,
                        color: context.env.storageProgressFill,
                        backgroundColor: const Color(0x1AFFFFFF),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OmniIcon(
                icon: OmniIcons.chevron,
                size: 17,
                color: context.env.inkMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分区卡图标映射：与设计原型一致的描边图标集。
OmniIconsData _sectionGlyph(FileManagerSection? section) {
  return switch (section) {
    FileManagerSection.allFiles => OmniIcons.folder,
    FileManagerSection.recent => OmniIcons.clock,
    FileManagerSection.favorites => OmniIcons.heart,
    FileManagerSection.sharedWithMe => OmniIcons.share,
    FileManagerSection.offlineDownloads => OmniIcons.download,
    FileManagerSection.recycleBin => OmniIcons.close,
    _ => OmniIcons.grid,
  };
}

/// 分区卡（原型 file-categories 紧凑形态）：图标居上 + 单行标签。
class _HomeSectionCard extends StatelessWidget {
  const _HomeSectionCard({
    required this.section,
    required this.hint,
    required this.onTap,
  });

  final FileManagerSection? section;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = section!.labelOf(l10n);
    final glyph = _sectionGlyph(section);
    return Semantics(
      button: true,
      label: '$title, $hint',
      child: MobilePressable(
        semanticLabel: title,
        onTap: onTap,
        child: Container(
          height: 77,
          decoration: BoxDecoration(
            color: const Color(0x0CFFFFFF),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: context.env.line09),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OmniIcon(icon: glyph, size: 21, color: context.env.storageCloud),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xB8FFFFFF),
                  fontSize: AppTypography.labelSmall,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
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
    // 根级呈现：整屏遮罩盖住底部导航与迷你播放器，腾出完整纵向空间。
    useRootNavigator: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    // 托管态环境重绑后 filesColors 是玻璃半透明：贴底面板须实底。
    backgroundColor:
        MobileShellScope.isHosted(context) ? context.env.sheetSolid : null,
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
                        fontSize: 9, // ignore: font_size_whitelist
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                        color: context.env.inkFaint,
                      ),
                    ),
                  ),
                  for (final item in entry.value)
                    _MoreSheetRow(
                      icon: item.icon,
                      label: item.labelOf(l10n),
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

/// 更多分区抽屉行（环境皮肤：36r11 图标盒 + 标题 + chevron + 发丝线）。
class _MoreSheetRow extends StatelessWidget {
  const _MoreSheetRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.env.line07)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.env.accentInk.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 17, color: context.env.accentInk),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12, // ignore: font_size_whitelist
                    fontWeight: FontWeight.w600,
                    color: context.env.ink,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: context.env.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 原型 `.notif-group` 分组眉标（9px 字距 1.5 弱化大写）。
class _HomeToolsLabel extends StatelessWidget {
  const _HomeToolsLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 0, 2),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 9, // ignore: font_size_whitelist
          letterSpacing: 1.5,
          fontWeight: FontWeight.w700,
          color: context.env.inkFaint,
        ),
      ),
    );
  }
}

/// 原型 `.tool-shortcuts`：首页工作区工具入口（外部存储 / 导入任务 /
/// 上传队列），点击进入对应分区列表态。
///
/// 副题只取已加载的真实数据；分区数据要打开该分区才拉取，未加载时
/// 回退到分区说明文案，不编造计数。
class _HomeToolShortcuts extends StatelessWidget {
  const _HomeToolShortcuts({required this.state, required this.onOpenSection});

  final FileBrowserState state;
  final ValueChanged<FileManagerSection> onOpenSection;

  static bool _isOnlineAccount(ExternalStorageAccount account) {
    return switch (account.status.toUpperCase()) {
      'CONNECTED' || 'ONLINE' || 'ACTIVE' => true,
      _ => false,
    };
  }

  static bool _isRunningStatus(String status) {
    return switch (status.toUpperCase()) {
      'COMPLETED' || 'FAILED' || 'ERROR' || 'CANCELLED' || 'CANCELED' => false,
      _ => true,
    };
  }

  String _externalSubtitle(AppLocalizations l10n) {
    final accounts = state.externalAccounts;
    if (accounts.isEmpty) {
      return l10n.filesExternalStorageDesc;
    }
    final online = accounts.where(_isOnlineAccount).length;
    return l10n.filesHomeShortcutMountsOnline(online, accounts.length);
  }

  String _importSubtitle(AppLocalizations l10n) {
    final active =
        state.importTasks.where((task) => _isRunningStatus(task.status)).length;
    return active > 0
        ? l10n.filesHomeShortcutTasksActive(active)
        : l10n.filesImportTasksDesc;
  }

  String _uploadSubtitle(AppLocalizations l10n) {
    var remaining = 0;
    for (final task in state.localUploadTasks) {
      if (!FileBrowserState.isTerminalUploadStatus(task.status)) {
        remaining += (task.sizeBytes - task.uploadedBytes).clamp(
          0,
          task.sizeBytes,
        );
      }
    }
    for (final item in state.uploadQueue) {
      if (!FileBrowserState.isTerminalUploadStatus(item.status)) {
        remaining += (item.sizeBytes * (1 - item.progress)).round();
      }
    }
    return remaining > 0
        ? l10n.filesHomeShortcutUploadRemaining(formatFileSize(remaining))
        : l10n.filesUploadQueueDesc;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = <(FileManagerSection, OmniIconsData, String)>[
      (
        FileManagerSection.externalStorage,
        OmniIcons.device,
        _externalSubtitle(l10n),
      ),
      (
        FileManagerSection.importTasks,
        OmniIcons.download,
        _importSubtitle(l10n),
      ),
      (FileManagerSection.uploadQueue, OmniIcons.queue, _uploadSubtitle(l10n)),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < entries.length; index++) ...[
            if (index > 0) const SizedBox(height: 7),
            _HomeToolShortcutRow(
              icon: entries[index].$2,
              title: entries[index].$1.labelOf(l10n),
              detail: entries[index].$3,
              onTap: () => onOpenSection(entries[index].$1),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单行工具入口（原型 `.tool-shortcuts > button`：58 高 r15 卡面 +
/// 酸绿首图标 + 名称/说明 + 弱化箭头）。
class _HomeToolShortcutRow extends StatelessWidget {
  const _HomeToolShortcutRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final OmniIconsData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MobilePressable(
      semanticLabel: title,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0x0CFFFFFF),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: context.env.line07),
        ),
        child: Row(
          children: [
            OmniIcon(icon: icon, size: 18, color: context.env.accentInk),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11, // ignore: font_size_whitelist
                      fontWeight: FontWeight.w700,
                      color: context.env.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9, // ignore: font_size_whitelist
                      color: context.env.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 11),
            OmniIcon(
              icon: OmniIcons.chevron,
              size: 16,
              color: context.env.ink40,
            ),
          ],
        ),
      ),
    );
  }
}

/// 目录原地展开态的内联返回上级栏：一级目录回空间根，更深层回上级。
class _InlineGoUpBar extends StatelessWidget {
  const _InlineGoUpBar({required this.state, required this.controller});

  final FileBrowserState state;
  final FileBrowserController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final crumbs = state.breadcrumbs;
    final atFirstLevel = crumbs.length == 1;
    final label =
        atFirstLevel
            ? (state.spaceType == 'SHARED'
                ? l10n.filesSharedSpace
                : l10n.filesHomeTabMyFiles)
            : crumbs[crumbs.length - 2].name;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.env.line07)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            unawaited(
              atFirstLevel
                  ? controller.goToRoot()
                  : controller.goToBreadcrumb(crumbs.length - 2),
            );
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Icon(
                  Icons.expand_less_rounded,
                  size: 20,
                  color: context.env.accentInk,
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.videoBackToParentNode,
                  style: TextStyle(
                    fontSize: 11, // ignore: font_size_whitelist
                    fontWeight: FontWeight.w600,
                    color: context.env.ink,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 10, // ignore: font_size_whitelist
                      color: context.env.inkFaint,
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
