part of 'desktop_files_page.dart';

/// 文件检查器的数据装配与侧栏内嵌视图（单选缩略图、共享入口、历史版本与多选汇总）。
extension _FilesPageInspector on _DesktopFilesPageState {
  DesktopDetailData _buildFileDetailData(
    AppLocalizations l10n,
    FileNode node, {
    required bool sharedSpace,
    FileBrowserController? controller,
    bool recycle = false,
  }) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final isShared = sharedSpace || node.spaceType == SpaceType.shared;
    final FileBrowserController activeController =
        controller ?? ref.read(fileBrowserControllerProvider.notifier);
    final updatedAt = node.updatedAt?.toLocal();
    final modifiedText =
        updatedAt == null
            ? '—'
            : '${updatedAt.year}-${updatedAt.month.toString().padLeft(2, '0')}-${updatedAt.day.toString().padLeft(2, '0')} '
                '${updatedAt.hour.toString().padLeft(2, '0')}:${updatedAt.minute.toString().padLeft(2, '0')}';

    final extraActions = <DesktopDetailAction>[
      if (!recycle && !node.isFolder && !isShared)
        DesktopDetailAction(
          label: l10n.filesDownload,
          icon: DesktopIcons.download,
          onPressed: (_, _) => unawaited(_openDownload(activeController, node)),
        ),
      if (!recycle && !isShared)
        DesktopDetailAction(
          label:
              node.favorited ? l10n.filesRemoveFavorite : l10n.filesAddFavorite,
          icon: node.favorited ? DesktopIcons.starFilled : DesktopIcons.star,
          onPressed:
              (_, _) => unawaited(_toggleFavorite(activeController, node)),
        ),
      if (!recycle)
        DesktopDetailAction(
          label: l10n.filesRename,
          icon: DesktopIcons.edit,
          onPressed: (ctx, _) => _showRenameDialog(ctx, activeController, node),
        ),
    ];

    return DesktopDetailData(
      id: 'file:${node.id}',
      kind: 'file',
      title: node.name,
      subtitle:
          node.isFolder
              ? l10n.desktopFilesKindFolder
              : formatFileSize(node.sizeBytes),
      isFolder: node.isFolder,
      fallbackIcon: _fileIcon(node),
      badge: isShared ? l10n.desktopFilesSharedBadge : null,
      squareArt: true,
      customPreview: _FileInspectorPreview(node: node),
      factsLabel: l10n.desktopFileSection,
      facts: [
        MapEntry(
          l10n.filesColumnType,
          node.isFolder
              ? l10n.desktopFilesKindFolder
              : (node.mimeType ?? node.nodeType),
        ),
        MapEntry(
          l10n.desktopFilesSize,
          node.isFolder ? '—' : formatFileSize(node.sizeBytes),
        ),
        MapEntry(l10n.desktopFilesModified, modifiedText),
        MapEntry(
          isZh ? '完整路径' : 'Path',
          node.normalizedPath.isEmpty ? '/' : node.normalizedPath,
        ),
        MapEntry(
          l10n.filesGroupSharing,
          isShared ? l10n.desktopFilesSharedBadge : l10n.desktopFilesPrivate,
        ),
      ],
      primary: DesktopDetailAction(
        label: l10n.desktopFilesOpen,
        icon: node.isFolder ? DesktopIcons.folder : DesktopIcons.eye,
        onPressed: (ctx, r) {
          if (node.isFolder) {
            final ctrl = r.read(fileBrowserControllerProvider.notifier);
            unawaited(
              isShared
                  ? ctrl.openSharedSpaceFolder(node)
                  : ctrl.openFolder(node),
            );
            return;
          }
          desktopPush(ctx, DesktopRoutes.filePreview(node.id));
        },
      ),
      secondary:
          !recycle && !isShared
              ? DesktopDetailAction(
                label: l10n.filesShare,
                icon: DesktopIcons.share,
                onPressed:
                    (ctx, _) => _showShareDialog(ctx, activeController, node),
              )
              : !recycle && !node.isFolder
              ? DesktopDetailAction(
                label: l10n.filesDownload,
                icon: DesktopIcons.download,
                onPressed:
                    (_, _) => unawaited(_openDownload(activeController, node)),
              )
              : null,
      extraActions: extraActions,
      extraSection:
          recycle
              ? null
              : _FileInspectorExtraSection(
                key: ValueKey<String>('file-inspector-extra-${node.id}'),
                node: node,
                controller: activeController,
                sharedSpace: isShared,
              ),
    );
  }

  DesktopDetailData _buildMultiSelectionDetailData(
    AppLocalizations l10n,
    List<FileNode> nodes, {
    required FileBrowserState state,
    required FileBrowserController controller,
  }) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final recycle = state.section == FileManagerSection.recycleBin;
    final sharedSpace =
        state.spaceType == 'SHARED' ||
        state.section == FileManagerSection.sharedSpace;
    final folderCount = nodes.where((n) => n.isFolder).length;
    final fileCount = nodes.length - folderCount;
    final totalBytes = nodes.fold<int>(
      0,
      (sum, node) => sum + (node.isFolder ? 0 : node.sizeBytes),
    );

    final extraActions = <DesktopDetailAction>[
      if (!recycle)
        DesktopDetailAction(
          label:
              sharedSpace ? l10n.filesMoveToPersonal : l10n.filesMoveToShared,
          icon: DesktopIcons.moveRight,
          onPressed:
              (_, _) => unawaited(
                _moveSelectedToSpace(controller, state, toShared: !sharedSpace),
              ),
        ),
      if (!recycle)
        DesktopDetailAction(
          label: l10n.desktopFilesMoveToRecycle,
          icon: DesktopIcons.trash,
          danger: true,
          onPressed: (_, _) => unawaited(_deleteSelected(controller, state)),
        ),
    ];

    return DesktopDetailData(
      id: 'files-multi:${nodes.map((n) => n.id).join(",")}',
      kind: 'file',
      title: isZh ? '已选 ${nodes.length} 项' : '${nodes.length} items selected',
      subtitle:
          isZh
              ? '总大小 ${formatFileSize(totalBytes)}'
              : 'Total ${formatFileSize(totalBytes)}',
      fallbackIcon: DesktopIcons.check,
      badge: '${nodes.length}',
      squareArt: true,
      factsLabel: isZh ? '批量汇总' : 'SELECTION SUMMARY',
      facts: [
        MapEntry(l10n.desktopFilesFilterFolders, '$folderCount'),
        MapEntry(l10n.desktopFilesFilesGroup, '$fileCount'),
        MapEntry(l10n.desktopFilesSize, formatFileSize(totalBytes)),
        MapEntry(
          l10n.filesGroupSharing,
          sharedSpace ? l10n.importToSharedSpace : l10n.importToPersonalSpace,
        ),
      ],
      primary:
          recycle
              ? DesktopDetailAction(
                label: l10n.filesRestore,
                icon: DesktopIcons.undo,
                onPressed: (_, _) => unawaited(_restoreSelected(controller)),
              )
              : fileCount > 0
              ? DesktopDetailAction(
                label: l10n.filesDownload,
                icon: DesktopIcons.download,
                onPressed:
                    (_, _) => unawaited(_downloadSelected(state, controller)),
              )
              : null,
      secondary:
          recycle
              ? DesktopDetailAction(
                label: l10n.desktopFilesDeleteForever,
                icon: DesktopIcons.trash,
                danger: true,
                onPressed: (ctx, _) => _showPurgeDialog(ctx, controller, nodes),
              )
              : DesktopDetailAction(
                label: l10n.filesCancel,
                icon: DesktopIcons.close,
                onPressed: (_, r) {
                  controller.clearSelection();
                  r.read(desktopShellProvider.notifier).clearDetail();
                },
              ),
      extraActions: extraActions,
    );
  }

  void _syncSelectionDetail({FileNode? fallbackNode}) {
    if (!mounted) {
      return;
    }
    final state = ref.read(fileBrowserControllerProvider).asData?.value;
    if (state == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final selectedNodes = _selectedNodes(state);
    final shell = ref.read(desktopShellProvider.notifier);
    if (selectedNodes.isEmpty) {
      if (fallbackNode != null &&
          state.selectedFileIds.contains(fallbackNode.id)) {
        final sharedSpace =
            state.spaceType == 'SHARED' ||
            state.section == FileManagerSection.sharedSpace;
        shell.selectDetail(
          _buildFileDetailData(
            l10n,
            fallbackNode,
            sharedSpace: sharedSpace,
            controller: controller,
            recycle: state.section == FileManagerSection.recycleBin,
          ),
        );
        return;
      }
      shell.clearDetail();
      return;
    }
    if (selectedNodes.length == 1) {
      final sharedSpace =
          state.spaceType == 'SHARED' ||
          state.section == FileManagerSection.sharedSpace;
      shell.selectDetail(
        _buildFileDetailData(
          l10n,
          selectedNodes.first,
          sharedSpace: sharedSpace,
          controller: controller,
          recycle: state.section == FileManagerSection.recycleBin,
        ),
      );
      return;
    }
    shell.selectDetail(
      _buildMultiSelectionDetailData(
        l10n,
        selectedNodes,
        state: state,
        controller: controller,
      ),
    );
  }
}

/// 文件检查器缩略图预览：图片/含封面的媒体文件渲染真实缩略图，其余文件渲染真实类型图标。
class _FileInspectorPreview extends ConsumerWidget {
  const _FileInspectorPreview({required this.node});

  final FileNode node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final icon = _fileIcon(node);
    final fallback = ColoredBox(
      color: skin.raise2,
      child: Center(child: Icon(icon, size: 46, color: skin.accent)),
    );
    if (node.isFolder) {
      return fallback;
    }
    final coverFileId = node.coverFileId;
    final isImage = node.mimeType?.toLowerCase().startsWith('image/') == true;
    final targetId =
        coverFileId != null && coverFileId.isNotEmpty
            ? coverFileId
            : (isImage ? node.id : null);
    if (targetId == null) {
      return fallback;
    }
    final url = ref.watch(fileDownloadUrlProvider(targetId)).asData?.value;
    if (url == null || url.isEmpty) {
      return fallback;
    }
    return DesktopCover(
      url: url,
      kind: DesktopCoverKind.network,
      fallback: fallback,
      fallbackIcon: icon,
      cacheKey: 'desktop-file-inspector-$targetId',
      iconSize: 46,
    );
  }
}

/// 文件检查器底部扩展区：展示共享状态入口并收编历史版本记录（原 `_DetailsDialog` 能力）。
class _FileInspectorExtraSection extends StatefulWidget {
  const _FileInspectorExtraSection({
    super.key,
    required this.node,
    required this.controller,
    required this.sharedSpace,
  });

  final FileNode node;
  final FileBrowserController controller;
  final bool sharedSpace;

  @override
  State<_FileInspectorExtraSection> createState() =>
      _FileInspectorExtraSectionState();
}

class _FileInspectorExtraSectionState
    extends State<_FileInspectorExtraSection> {
  List<FileVersion>? _versions;
  bool _loadingVersions = false;
  Object? _versionsError;

  @override
  void initState() {
    super.initState();
    if (!widget.node.isFolder) {
      _loadingVersions = true;
      unawaited(_loadVersions());
    }
  }

  @override
  void didUpdateWidget(covariant _FileInspectorExtraSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _versions = null;
      _versionsError = null;
      if (!widget.node.isFolder) {
        _loadingVersions = true;
        unawaited(_loadVersions());
      } else {
        _loadingVersions = false;
      }
    }
  }

  Future<void> _loadVersions() async {
    try {
      final versions = await widget.controller.listFileVersions(widget.node.id);
      if (!mounted) return;
      setState(() {
        _versions = versions;
        _loadingVersions = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _versionsError = error;
        _loadingVersions = false;
      });
    }
  }

  Future<void> _restore(FileVersion version) async {
    final l10n = AppLocalizations.of(context);
    try {
      await widget.controller.restoreFileVersion(widget.node, version.id);
      if (!mounted) return;
      showDesktopToast(context, l10n.filesRestore, icon: DesktopIcons.undo);
      setState(() {
        _loadingVersions = true;
        _versionsError = null;
      });
      unawaited(_loadVersions());
    } on Object catch (error) {
      if (!mounted) return;
      showDesktopToast(
        context,
        failureToast(l10n, l10n.filesRestore, error),
        kind: DesktopToastKind.error,
        icon: DesktopIcons.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.sharedSpace) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: skin.raise,
              borderRadius: BorderRadius.circular(DesktopMetrics.radiusSmall),
              border: Border.all(color: skin.line),
            ),
            child: Row(
              children: [
                Icon(DesktopIcons.share, size: 15, color: skin.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isZh ? '外链与协作者共享' : 'Link & collaborator sharing',
                    style: DesktopType.caption(skin.text2),
                  ),
                ),
                DesktopLink(
                  label: l10n.filesShare,
                  onPressed:
                      () => _showShareDialog(
                        context,
                        widget.controller,
                        widget.node,
                      ),
                ),
              ],
            ),
          ),
        ],
        if (!widget.node.isFolder) ...[
          const SizedBox(height: 14),
          DesktopEyebrow(l10n.desktopFilesVersions),
          const SizedBox(height: 8),
          if (_loadingVersions)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: DesktopSkeletonBox(
                width: double.infinity,
                height: 28,
                radius: 8,
              ),
            )
          else if (_versionsError != null)
            Text(
              failureToast(l10n, l10n.desktopFilesVersions, _versionsError!),
              style: DesktopType.caption(DesktopPalette.bad),
            )
          else if (_versions == null || _versions!.isEmpty)
            Text(
              isZh ? '暂无历史版本记录' : 'No version history yet',
              style: DesktopType.caption(skin.text3),
            )
          else
            for (final version in _versions!)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color:
                            version.isCurrent
                                ? skin.accentWash(0.14)
                                : skin.raise,
                        borderRadius: BorderRadius.circular(
                          DesktopMetrics.radiusPill,
                        ),
                      ),
                      child: Text(
                        'v${version.versionNo}',
                        style: DesktopType.nano(
                          version.isCurrent ? skin.accent : skin.text3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${formatFileSize(version.sizeBytes)} · ${_formatDate(version.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.caption(skin.text2),
                      ),
                    ),
                    if (!version.isCurrent)
                      DesktopLink(
                        label: l10n.filesRestore,
                        trailing: false,
                        onPressed: () => unawaited(_restore(version)),
                      ),
                  ],
                ),
              ),
        ],
      ],
    );
  }
}
