part of 'file_browser_page.dart';

/// 共享给我表格的格式标签：按 MIME 分类给短标签。
String _formatOf(FileNode file, AppLocalizations l10n) {
  if (file.isFolder) {
    return l10n.filesFolder;
  }
  final mime = file.mimeType ?? '';
  if (mime.startsWith('image/')) {
    return 'IMG';
  }
  if (mime.startsWith('video/')) {
    return 'VIDEO';
  }
  if (mime.startsWith('audio/')) {
    return 'AUDIO';
  }
  if (mime.contains('pdf')) {
    return 'PDF';
  }
  if (mime.contains('zip') || mime.contains('rar') || mime.contains('7z')) {
    return 'ARCHIVE';
  }
  if (mime.startsWith('text/')) {
    return 'TXT';
  }
  return 'FILE';
}

/// 共享空间与外链分享两个子页工作区（自 file_browser_page_subpage 拆出）。

class _SharedWithMeWorkspace extends ConsumerStatefulWidget {
  const _SharedWithMeWorkspace({required this.state});

  final FileBrowserState state;

  @override
  ConsumerState<_SharedWithMeWorkspace> createState() =>
      _SharedWithMeWorkspaceState();
}

class _SharedWithMeWorkspaceState
    extends ConsumerState<_SharedWithMeWorkspace> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(fileBrowserControllerProvider.notifier).refreshForRealtime();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = widget.state.sharedWithMe;
    final owners = items.map((i) => i.ownerUserId).toSet().length;
    final totalSize = items.fold<int>(0, (sum, i) => sum + i.file.sizeBytes);
    final folders = items.where((i) => i.file.isFolder).length;
    final locale = Localizations.localeOf(context).toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubHeader(
          title: FileManagerSection.sharedWithMe.labelOf(l10n),
          subtitle: FileManagerSection.sharedWithMe.descriptionOf(l10n),
        ),
        const SizedBox(height: 16),
        _SubMetricStrip(
          cards: [
            _MetricCard(
              label: l10n.filesMetricSharedOwners,
              value: owners.toString(),
              detail: l10n.filesSharedWithMeDesc,
              color: context.filesColors.onSurface,
            ),
            _MetricCard(
              label: l10n.filesMetricSharedItems,
              value: items.length.toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.onSurface,
            ),
            _MetricCard(
              label: l10n.filesMetricSharedSize,
              value: formatFileSize(totalSize),
              detail: l10n.filesCurrentViewTotal,
              color: context.filesColors.onSurface,
            ),
            _MetricCard(
              label: l10n.filesFolders,
              value: folders.toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.onSurface,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: _SubTable(
              columns: [
                _SubColumn(l10n.filesColumnName, flex: 2),
                _SubColumn(l10n.filesColumnUploader, flex: 1),
                _SubColumn(l10n.filesColumnFormat, width: 88),
                _SubColumn(l10n.filesColumnSharedAt, width: 116),
                _SubColumn(l10n.filesColumnExpiresAt, width: 108),
                _SubColumn(l10n.filesColumnSize, width: 96),
                _SubColumn(l10n.filesFileActions, width: 96),
              ],
              rows: [
                for (final item in items)
                  _SubRow(
                    onTap:
                        item.file.isFolder
                            ? null
                            : () => _openFilePreview(context, item.file),
                    cells: [
                      _SubNameCell(
                        name: item.file.name,
                        detail: item.file.normalizedPath,
                        isFolder: item.file.isFolder,
                      ),
                      // 上传者展示可读名；上传者账户可能已注销，缺失时回退占位。
                      _SubMono(
                        (item.file.uploaderName ?? '').isNotEmpty
                            ? item.file.uploaderName!
                            : '—',
                      ),
                      _SubMono(_formatOf(item.file, l10n)),
                      _SubMono(
                        item.sharedAt == null
                            ? '—'
                            : DateFormat(
                              'MM-dd HH:mm',
                              locale,
                            ).format(item.sharedAt!),
                      ),
                      _SubMono(
                        item.expiresAt == null
                            ? l10n.filesSharePermanent
                            : DateFormat(
                              'yyyy-MM-dd',
                              locale,
                            ).format(item.expiresAt!),
                      ),
                      _SubMono(
                        item.file.isFolder
                            ? l10n.filesFolder
                            : formatFileSize(item.file.sizeBytes),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _SubAction(
                          label: l10n.filesPreview,
                          onTap:
                              item.file.isFolder
                                  ? null
                                  : () => _openFilePreview(context, item.file),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        WorkstationPaginationBar(
          currentPage: widget.state.sharedWithMeMeta.page,
          totalPages: widget.state.sharedWithMeMeta.totalPages,
          totalElements: widget.state.sharedWithMeMeta.totalElements,
          rowsPerPage: widget.state.sharedWithMeMeta.size,
          busy: widget.state.isBusy,
          onPageChanged:
              (page) => ref
                  .read(fileBrowserControllerProvider.notifier)
                  .showSharedWithMe(page: page),
          onRowsPerPageChanged:
              (size) => ref
                  .read(fileBrowserControllerProvider.notifier)
                  .showSharedWithMe(page: 0, size: size),
        ),
      ],
    );
  }
}

// ───────────────────────── 我的分享 / 分享链接管理（06 / 07） ─────────────────────────

enum _ShareFilter { all, active, expired, revoked }

String _derivedShareState(FileShareLink share) {
  final status = share.status.toUpperCase();
  if (share.disabledAt != null || status == 'REVOKED' || status == 'DISABLED') {
    return 'REVOKED';
  }
  if (status == 'EXPIRED' ||
      status == 'EXHAUSTED' ||
      (share.expiresAt != null && share.expiresAt!.isBefore(DateTime.now()))) {
    return 'EXPIRED';
  }
  return 'ACTIVE';
}

class _ShareWorkspace extends ConsumerStatefulWidget {
  const _ShareWorkspace({
    required this.title,
    required this.subtitle,
    required this.shares,
    required this.state,
    this.managementMode = false,
  });

  final String title;
  final String subtitle;
  final List<FileShareLink> shares;
  final FileBrowserState state;
  final bool managementMode;

  @override
  ConsumerState<_ShareWorkspace> createState() => _ShareWorkspaceState();
}

class _ShareWorkspaceState extends ConsumerState<_ShareWorkspace> {
  _ShareFilter _filter = _ShareFilter.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !widget.state.isBusy;
    final shares = widget.shares;
    final counts = {
      'ACTIVE': shares.where((s) => _derivedShareState(s) == 'ACTIVE').length,
      'EXPIRED': shares.where((s) => _derivedShareState(s) == 'EXPIRED').length,
      'REVOKED': shares.where((s) => _derivedShareState(s) == 'REVOKED').length,
    };
    final filtered =
        shares.where((share) {
          return switch (_filter) {
            _ShareFilter.all => true,
            _ShareFilter.active => _derivedShareState(share) == 'ACTIVE',
            _ShareFilter.expired => _derivedShareState(share) == 'EXPIRED',
            _ShareFilter.revoked => _derivedShareState(share) == 'REVOKED',
          };
        }).toList();
    final locale = Localizations.localeOf(context).toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubHeader(
          title: widget.title,
          subtitle: widget.subtitle,
          // 作用域切换：我的创建 / 全部链接（全部仅系统配置管理权限可见）。
          actions: [
            if (ref.watch(userCapabilitiesProvider).canManageSystemConfig) ...[
              _CategoryCapsule(
                label: l10n.filesShareScopeMine,
                icon: Icons.person_outline,
                isActive: !widget.state.shareScopeAll,
                enabled: true,
                onTap:
                    () => _runFileAction(
                      context,
                      () =>
                          ref
                              .read(fileBrowserControllerProvider.notifier)
                              .showMyShares(),
                    ),
              ),
              const SizedBox(width: 6),
              _CategoryCapsule(
                label: l10n.filesShareScopeAll,
                icon: Icons.public_outlined,
                isActive: widget.state.shareScopeAll,
                enabled: true,
                onTap:
                    () => _runFileAction(
                      context,
                      () =>
                          ref
                              .read(fileBrowserControllerProvider.notifier)
                              .showShareLinks(),
                    ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _SubMetricStrip(
          cards: [
            _MetricCard(
              label: l10n.filesMetricTotalShares,
              value: shares.length.toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.onSurface,
            ),
            _MetricCard(
              label: l10n.filesMetricActiveShares,
              value: counts['ACTIVE'].toString(),
              detail: l10n.filesCurrentView,
              color: FilesWorkstationPalette.emerald,
            ),
            _MetricCard(
              label: l10n.filesMetricExpiredShares,
              value: counts['EXPIRED'].toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.onSurfaceVariant,
            ),
            _MetricCard(
              label: l10n.filesMetricRevokedShares,
              value: counts['REVOKED'].toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.error,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SubChipsBar(
          chips: [
            _SubChip(
              label: '${l10n.filesStatusFilterAll} (${shares.length})',
              active: _filter == _ShareFilter.all,
              onTap: () => setState(() => _filter = _ShareFilter.all),
            ),
            _SubChip(
              label: '${l10n.filesShareActive} (${counts['ACTIVE']})',
              active: _filter == _ShareFilter.active,
              onTap: () => setState(() => _filter = _ShareFilter.active),
            ),
            _SubChip(
              label: '${l10n.filesShareExpired} (${counts['EXPIRED']})',
              active: _filter == _ShareFilter.expired,
              onTap: () => setState(() => _filter = _ShareFilter.expired),
            ),
            _SubChip(
              label: '${l10n.filesShareRevoked} (${counts['REVOKED']})',
              active: _filter == _ShareFilter.revoked,
              onTap: () => setState(() => _filter = _ShareFilter.revoked),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: _SubTable(
              columns: [
                _SubColumn(l10n.filesColumnName, flex: 3),
                _SubColumn(l10n.filesShareLink, width: 128),
                _SubColumn(l10n.filesShareExtract, width: 96),
                _SubColumn(l10n.filesShareAccess, width: 88),
                _SubColumn(l10n.filesShareCreated, width: 108),
                _SubColumn(l10n.filesShareExpires, width: 108),
                _SubColumn(l10n.filesColumnStatus, width: 96),
                _SubColumn(l10n.filesFileActions, width: 140),
              ],
              rows: [
                for (final share in filtered)
                  _SubRow(
                    cells: [
                      _SubNameCell(
                        name: share.resourceName,
                        detail:
                            share.resourceType.toUpperCase() == 'FOLDER'
                                ? l10n.filesFolder
                                : share.resourceName,
                        isFolder: share.resourceType.toUpperCase() == 'FOLDER',
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(child: _SubMono(share.shareCode)),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.content_copy_rounded,
                            size: 12,
                            color: context.filesColors.onSurfaceVariant,
                          ),
                        ],
                      ),
                      _SubMono(
                        share.generatedPassword ?? l10n.filesSharePublic,
                      ),
                      _SubMono(
                        '${share.accessCount}'
                        '/${share.maxAccessCount ?? '∞'}',
                      ),
                      _SubMono(
                        share.createdAt == null
                            ? '—'
                            : DateFormat(
                              'yyyy-MM-dd',
                              locale,
                            ).format(share.createdAt!),
                      ),
                      _SubMono(
                        share.expiresAt == null
                            ? l10n.filesSharePermanent
                            : DateFormat(
                              'yyyy-MM-dd',
                              locale,
                            ).format(share.expiresAt!),
                      ),
                      _ShareStateText(share: share, l10n: l10n, locale: locale),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _SubAction(
                              label: l10n.filesOpEdit,
                              onTap:
                                  enabled
                                      ? () => ShareLinkSheet.show(
                                        context,
                                        existingShare: share,
                                        file: FileNode(
                                          id: share.resourceId,
                                          parentId: null,
                                          name: share.resourceName,
                                          isFolder:
                                              share.resourceType
                                                  .toUpperCase() ==
                                              'FOLDER',
                                          nodeType: share.resourceType,
                                          normalizedPath: share.resourceName,
                                          sizeBytes: 0,
                                          updatedAt: share.createdAt,
                                        ),
                                      )
                                      : null,
                            ),
                            const SizedBox(width: 6),
                            _SubAction(
                              label: l10n.filesOpRevoke,
                              destructive: true,
                              onTap:
                                  enabled
                                      ? () => _confirmAndRun(
                                        context,
                                        title: l10n.filesRevokeShareConfirm,
                                        message: l10n.filesRevokeShareMessage(
                                          share.resourceName,
                                        ),
                                        confirmLabel: l10n.filesRevokeShare,
                                        action:
                                            () => controller.revokeShare(share),
                                      )
                                      : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        WorkstationPaginationBar(
          currentPage: widget.state.sharesMeta.page,
          totalPages: widget.state.sharesMeta.totalPages,
          totalElements: widget.state.sharesMeta.totalElements,
          rowsPerPage: widget.state.sharesMeta.size,
          busy: widget.state.isBusy,
          onPageChanged:
              (page) => _reloadSharesPage(
                ref,
                scopeAll: widget.state.shareScopeAll,
                page: page,
              ),
          onRowsPerPageChanged:
              (size) => _reloadSharesPage(
                ref,
                scopeAll: widget.state.shareScopeAll,
                page: 0,
                size: size,
              ),
        ),
      ],
    );
  }
}

/// 分享状态紧凑着色文本：无徽章底盒，语义色直接上字，释放列宽。
class _ShareStateText extends StatelessWidget {
  const _ShareStateText({
    required this.share,
    required this.l10n,
    required this.locale,
  });

  final FileShareLink share;
  final AppLocalizations l10n;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final state = _derivedShareState(share);
    final (label, color) = switch (state) {
      'REVOKED' => (l10n.filesShareRevoked, context.filesColors.error),
      'EXPIRED' => (
        l10n.filesShareExpiredShort,
        context.filesColors.onSurfaceVariant,
      ),
      _ => (
        share.expiresAt == null
            ? l10n.filesSharePermanent
            : DateFormat('MM-dd', locale).format(share.expiresAt!),
        FilesWorkstationPalette.emerald,
      ),
    };
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: AppTypography.monoFamily,
        fontFamilyFallback: AppTypography.monoFamilyFallback,
        fontSize: AppTypography.labelSmall,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }
}

// ───────────────────────── 上传队列（08） ─────────────────────────

/// 分享页翻页：按作用域分派我的分享/全部链接。
void _reloadSharesPage(
  WidgetRef ref, {
  required bool scopeAll,
  required int page,
  int? size,
}) {
  final controller = ref.read(fileBrowserControllerProvider.notifier);
  if (scopeAll) {
    controller.showShareLinks(page: page, size: size);
  } else {
    controller.showMyShares(page: page, size: size);
  }
}
