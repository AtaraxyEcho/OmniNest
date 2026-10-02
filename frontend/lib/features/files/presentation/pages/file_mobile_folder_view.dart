part of 'file_browser_page.dart';

/// 样例 FolderView 的托管移动工作区头：模块横幅（返回圆钮 + 目录名/
/// 分区名 + 路径·计数副题 + 上传圆钮）。
class _MobileFolderHeader extends StatelessWidget {
  const _MobileFolderHeader({
    required this.state,
    required this.controller,
    required this.onBack,
  });

  final FileBrowserState state;
  final FileBrowserController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title =
        state.section == FileManagerSection.allFiles &&
                state.breadcrumbs.isNotEmpty
            ? state.breadcrumbs.last.name
            : state.section.labelOf(l10n);
    final crumbs =
        state.section == FileManagerSection.allFiles
            ? state.breadcrumbs.map((node) => node.name).join(' / ')
            : state.section.labelOf(l10n);
    final subtitle =
        '$crumbs · ${state.files.length} ${l10n.filesFolderItemCount(state.files.length)}';
    return MobileModuleHeader(
      title: title,
      subtitle: subtitle,
      onBack: onBack,
      actions: [
        MobileGlassIconButton(
          tooltip: l10n.portalQuickUpload,
          icon: Icons.add_rounded,
          onPressed: () => unawaited(_pickAndUploadFiles(context, controller)),
        ),
      ],
    );
  }
}

/// 样例 FolderView 三档分段（Files/Shared/Recycle），左对齐。
class _MobileFolderSegments extends ConsumerWidget {
  const _MobileFolderSegments({required this.state});

  final FileBrowserState state;

  static const _sections = <FileManagerSection>[
    FileManagerSection.allFiles,
    FileManagerSection.sharedSpace,
    FileManagerSection.recycleBin,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final effective =
        _sections.contains(state.section) ? state.section : _sections.first;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
        child: MobileSegmentedControl<FileManagerSection>(
          values: _sections,
          selected: effective,
          labelBuilder:
              (section) => switch (section) {
                FileManagerSection.allFiles => l10n.filesHomeTabMyFiles,
                FileManagerSection.sharedSpace => l10n.filesSharedSpace,
                _ => l10n.filesRecycleBin,
              },
          onSelected: (section) {
            unawaited(
              _runFileAction(context, () => controller.loadSection(section)),
            );
          },
        ),
      ),
    );
  }
}

/// Shared 档的分享管理入口（样例 share-manage-entry：酸绿 7% 底、
/// 居中图标 + 文案 + 箭头）。
class _MobileShareManageEntry extends StatelessWidget {
  const _MobileShareManageEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Material(
        color: MobileEnvColors.accent.withValues(alpha: 0.07),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OmniIcon(
                  icon: OmniIcons.share,
                  size: 17,
                  color: MobileEnvColors.ink,
                ),
                const SizedBox(width: 7),
                Text(
                  l10n.filesShareManageEntry,
                  style: const TextStyle(
                    fontSize: 10, // ignore: font_size_whitelist
                    fontWeight: FontWeight.w600,
                    color: MobileEnvColors.ink,
                  ),
                ),
                const SizedBox(width: 7),
                OmniIcon(
                  icon: OmniIcons.chevron,
                  size: 15,
                  color: MobileEnvColors.ink,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 样例 FolderView 的主体判定：三档分段覆盖的分区走托管行列表形态。
bool _isMobileFolderSection(FileManagerSection section) {
  return switch (section) {
    FileManagerSection.allFiles ||
    FileManagerSection.sharedSpace ||
    FileManagerSection.recycleBin => true,
    _ => false,
  };
}

/// 固定「返回上一级」栏：子目录内钉在分段与列表之间，点击回到上级目录。
class _MobileGoUpBar extends StatelessWidget {
  const _MobileGoUpBar({required this.parentName, required this.onTap});

  final String parentName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MobileEnvColors.line07)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(
                  Icons.expand_less_rounded,
                  size: 20,
                  color: MobileEnvColors.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context).videoBackToParentNode,
                  style: const TextStyle(
                    fontSize: 11, // ignore: font_size_whitelist
                    fontWeight: FontWeight.w600,
                    color: MobileEnvColors.ink,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    parentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 10, // ignore: font_size_whitelist
                      color: MobileEnvColors.inkFaint,
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
