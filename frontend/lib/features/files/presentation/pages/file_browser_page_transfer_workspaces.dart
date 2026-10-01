part of 'file_browser_page.dart';

/// 上传队列、离线下载、外部存储与导入任务四个子页工作区
/// （自 file_browser_page_subpage 拆出）。

class _UploadQueueWorkspace extends ConsumerWidget {
  const _UploadQueueWorkspace({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !state.isBusy;
    final localActive = state.inlineUploadTasks.length;
    final serverActive =
        state.uploadQueue
            .where(
              (item) => !FileBrowserState.isTerminalUploadStatus(item.status),
            )
            .length;
    final completed =
        state.uploadQueue
            .where((item) => item.status.toUpperCase() == 'COMPLETED')
            .length;
    final failed =
        state.uploadQueue
            .where((item) => item.status.toUpperCase() == 'FAILED')
            .length;
    final locale = Localizations.localeOf(context).toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubHeader(
          title: FileManagerSection.uploadQueue.labelOf(l10n),
          subtitle: FileManagerSection.uploadQueue.descriptionOf(l10n),
        ),
        const SizedBox(height: 16),
        _SubMetricStrip(
          cards: [
            _MetricCard(
              label: l10n.filesMetricUploading,
              value: localActive.toString(),
              detail: l10n.filesCurrentView,
              color: FilesWorkstationPalette.emerald,
            ),
            _MetricCard(
              label: l10n.filesMetricQueued,
              value: serverActive.toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.onSurface,
            ),
            _MetricCard(
              label: l10n.filesMetricCompleted,
              value: completed.toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.onSurface,
            ),
            _MetricCard(
              label: l10n.filesMetricFailed,
              value: failed.toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.error,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: _SubTable(
              columns: [
                _SubColumn(l10n.filesColumnName, flex: 3),
                _SubColumn(l10n.filesUploadOrigin, width: 72),
                _SubColumn(l10n.filesColumnSize, width: 96),
                _SubColumn(l10n.filesProgress, flex: 2),
                _SubColumn(l10n.filesColumnStatus, width: 96),
                _SubColumn(l10n.filesColumnUpdatedAt, width: 108),
                _SubColumn(l10n.filesColumnExpiresAt, width: 108),
                _SubColumn(l10n.filesFileActions, width: 140),
              ],
              rows: [
                for (final task in state.localUploadTasks)
                  _SubRow(
                    cells: [
                      _SubNameCell(
                        name: task.fileName,
                        detail: task.message ?? task.status,
                        isFolder: false,
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _StatusBadge(l10n.filesUploadOriginLocal),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: _SubMono(formatFileSize(task.sizeBytes)),
                      ),
                      _UploadProgressCell(
                        value: task.progress,
                        primary: '${(task.progress * 100).toInt()}%',
                        detail:
                            '${formatFileSize(task.uploadedBytes)} / '
                            '${formatFileSize(task.sizeBytes)}'
                            '${task.messageCurrent != null && task.messageTotal != null ? ' · ${task.messageCurrent}/${task.messageTotal}' : ''}',
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _StatusBadge(
                          _uploadStatusLabel(l10n, task.status),
                          tone: _uploadStatusTone(task.status),
                        ),
                      ),
                      _SubMono('—'),
                      _SubMono('—'),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (task.status == 'PAUSED')
                            _SubAction(
                              label: l10n.filesResumeUpload,
                              onTap:
                                  enabled
                                      ? () => _runFileAction(
                                        context,
                                        () => controller.resumeLocalUploadTask(
                                          task.id,
                                        ),
                                      )
                                      : null,
                            )
                          else if (task.status == 'RUNNING' ||
                              task.status == 'PENDING')
                            _SubAction(
                              label: l10n.filesPauseUpload,
                              onTap:
                                  enabled
                                      ? () => _runFileAction(
                                        context,
                                        () async => controller
                                            .pauseLocalUploadTask(task.id),
                                      )
                                      : null,
                            ),
                          const SizedBox(width: 6),
                          _SubAction(
                            label: l10n.filesDeleteTask,
                            destructive: true,
                            onTap:
                                enabled
                                    ? () => _confirmAndRun(
                                      context,
                                      title: l10n.filesDeleteUploadTask,
                                      message:
                                          l10n.filesDeleteUploadTaskMessage,
                                      confirmLabel: l10n.filesDeleteTask,
                                      action:
                                          () => controller
                                              .removeLocalUploadTask(task.id),
                                    )
                                    : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                for (final item in state.uploadQueue)
                  _SubRow(
                    cells: [
                      _SubNameCell(
                        name: item.fileName,
                        detail:
                            item.expiresAt == null
                                ? '—'
                                : DateFormat(
                                  'yyyy-MM-dd HH:mm',
                                  Localizations.localeOf(context).toString(),
                                ).format(item.expiresAt!),
                        isFolder: false,
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _StatusBadge(l10n.filesUploadOriginServer),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: _SubMono(formatFileSize(item.sizeBytes)),
                      ),
                      _UploadProgressCell(
                        value: item.progress,
                        primary: '${(item.progress * 100).toInt()}%',
                        detail:
                            '${item.uploadedParts}/${item.totalParts} '
                            '${l10n.filesUploadPartsUnit}',
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _StatusBadge(
                          _uploadStatusLabel(l10n, item.status),
                          tone: _uploadStatusTone(item.status),
                        ),
                      ),
                      _SubMono(
                        item.updatedAt == null
                            ? '—'
                            : DateFormat(
                              'MM-dd HH:mm',
                              locale,
                            ).format(item.updatedAt!),
                      ),
                      _SubMono(
                        item.expiresAt == null
                            ? '—'
                            : DateFormat(
                              'yyyy-MM-dd',
                              locale,
                            ).format(item.expiresAt!),
                      ),
                      _SubAction(
                        label: l10n.filesCancel,
                        destructive: true,
                        onTap:
                            enabled &&
                                    !FileBrowserState.isTerminalUploadStatus(
                                      item.status,
                                    )
                                ? () => _runFileAction(
                                  context,
                                  () => controller.deleteServerUploadSession(
                                    item,
                                  ),
                                )
                                : null,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        WorkstationPaginationBar(
          currentPage: state.uploadQueueMeta.page,
          totalPages: state.uploadQueueMeta.totalPages,
          totalElements: state.uploadQueueMeta.totalElements,
          rowsPerPage: state.uploadQueueMeta.size,
          busy: state.isBusy,
          onPageChanged: (page) => controller.showUploadQueue(page: page),
          onRowsPerPageChanged:
              (size) => controller.showUploadQueue(page: 0, size: size),
        ),
      ],
    );
  }
}

/// 上传进度富单元格：百分比主行 + 明细次行 + 2px 进度条。
class _UploadProgressCell extends StatelessWidget {
  const _UploadProgressCell({
    required this.value,
    required this.primary,
    required this.detail,
  });

  final double value;
  final String primary;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    // 右缘留白：子页表格列间零间距，全宽进度条不加内边距会直接顶到
    // 相邻状态徽章，视觉上与状态列连成一体。
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  primary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTypography.monoFamily,
                    fontFamilyFallback: AppTypography.monoFamilyFallback,
                    fontSize: AppTypography.labelSmall,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTypography.monoFamily,
                    fontFamilyFallback: AppTypography.monoFamilyFallback,
                    fontSize: AppTypography.labelMicro,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRect(
            child: SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                value: value,
                minHeight: 2,
                color: FilesWorkstationPalette.emerald,
                backgroundColor: colors.surfaceContainerHighest,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 上传状态统一文案。
String _uploadStatusLabel(AppLocalizations l10n, String status) {
  return switch (status.toUpperCase()) {
    'RUNNING' => l10n.filesStatusRunning,
    'PENDING' => l10n.filesStatusPending,
    'PAUSED' => l10n.filesStatusPaused,
    'COMPLETED' => l10n.filesStatusCompleted,
    'FAILED' => l10n.filesStatusFailed,
    'CONFLICT' => l10n.filesStatusConflict,
    _ => status,
  };
}

/// 上传状态语义色。
_BadgeTone _uploadStatusTone(String status) {
  return switch (status.toUpperCase()) {
    'COMPLETED' || 'RUNNING' => _BadgeTone.good,
    'FAILED' || 'CONFLICT' => _BadgeTone.bad,
    'PAUSED' || 'PENDING' => _BadgeTone.warn,
    _ => _BadgeTone.neutral,
  };
}

// ───────────────────────── 离线下载（09） ─────────────────────────

class _OfflineDownloadWorkspace extends ConsumerStatefulWidget {
  const _OfflineDownloadWorkspace({required this.state});

  final FileBrowserState state;

  @override
  ConsumerState<_OfflineDownloadWorkspace> createState() =>
      _OfflineDownloadWorkspaceState();
}

class _OfflineDownloadWorkspaceState
    extends ConsumerState<_OfflineDownloadWorkspace> {
  String _filter = 'ALL';

  Future<void> _createOfflineDownloadWithSpace(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final spaceSelection = await showSpaceSelectorSheet(context);
    if (spaceSelection == null || !context.mounted) {
      return;
    }
    final spaceType =
        spaceSelection == SpaceSelection.shared ? 'SHARED' : 'PERSONAL';
    await _showNameDialog(
      context: context,
      title: l10n.filesNewOfflineDownload,
      actionLabel: l10n.filesCreate,
      labelText: l10n.filesDownloadLink,
      hintText: l10n.filesOfflineDownloadHint,
      onSubmit:
          (uri) => controller.createOfflineDownload(uri, spaceType: spaceType),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !widget.state.isBusy;
    final tasks = widget.state.offlineTasks;
    final locale = Localizations.localeOf(context).toString();
    int countOf(String status) =>
        tasks.where((t) => t.status.toUpperCase() == status).length;
    final running = countOf('RUNNING') + countOf('DOWNLOADING');
    final completed = countOf('COMPLETED');
    final failed = countOf('FAILED');
    final filtered =
        tasks
            .where((t) => _filter == 'ALL' || t.status.toUpperCase() == _filter)
            .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubHeader(
          title: FileManagerSection.offlineDownloads.labelOf(l10n),
          subtitle: FileManagerSection.offlineDownloads.descriptionOf(l10n),
          actions: [
            FilesActionButton(
              label: l10n.filesNewOfflineDownload,
              icon: Icons.add_rounded,
              variant: FilesActionButtonVariant.primary,
              onPressed:
                  enabled
                      ? () =>
                          unawaited(_createOfflineDownloadWithSpace(context))
                      : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SubMetricStrip(
          cards: [
            _MetricCard(
              label: l10n.filesMetricUploading,
              value: running.toString(),
              detail: l10n.filesCurrentView,
              color: FilesWorkstationPalette.emerald,
            ),
            _MetricCard(
              label: l10n.filesMetricQueued,
              value: countOf('PENDING').toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.onSurface,
            ),
            _MetricCard(
              label: l10n.filesMetricCompleted,
              value: completed.toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.onSurface,
            ),
            _MetricCard(
              label: l10n.filesMetricFailed,
              value: failed.toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.error,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SubChipsBar(
          chips: [
            _SubChip(
              label: '${l10n.filesStatusFilterAll} (${tasks.length})',
              active: _filter == 'ALL',
              onTap: () => setState(() => _filter = 'ALL'),
            ),
            _SubChip(
              label: l10n.filesStatusDownloading,
              active: _filter == 'RUNNING',
              onTap: () => setState(() => _filter = 'RUNNING'),
            ),
            _SubChip(
              label: l10n.filesStatusCompleted,
              active: _filter == 'COMPLETED',
              onTap: () => setState(() => _filter = 'COMPLETED'),
            ),
            _SubChip(
              label: l10n.filesStatusFailed,
              active: _filter == 'FAILED',
              onTap: () => setState(() => _filter = 'FAILED'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: _SubTable(
              columns: [
                _SubColumn(l10n.filesTaskSource, flex: 3),
                _SubColumn(l10n.filesColumnType, width: 88),
                _SubColumn(l10n.filesColumnSize, width: 96),
                _SubColumn(l10n.filesProgress, flex: 2),
                _SubColumn(l10n.filesOfflineSpeed, width: 100),
                _SubColumn(l10n.filesColumnStatus, width: 88),
                _SubColumn(l10n.filesColumnCreatedAt, width: 108),
                _SubColumn(l10n.filesFileActions, width: 96),
              ],
              rows: [
                for (final task in filtered)
                  _SubRow(
                    cells: [
                      // 失败任务把错误摘要提到次行：仅靠徽章无法解释失败原因。
                      _SubNameCell(
                        name: task.fileName ?? task.sourceUri,
                        detail:
                            (task.errorSummary ?? '').isNotEmpty
                                ? task.errorSummary!
                                : task.sourceUri,
                        isFolder: false,
                      ),
                      _SubMono(
                        (Uri.tryParse(task.sourceUri)?.scheme ?? 'http')
                            .toUpperCase(),
                      ),
                      _SubMono(formatFileSize(task.totalBytes)),
                      _SubProgressCell(
                        value: task.progress,
                        label:
                            '${(task.progress * 100).toStringAsFixed(1)}%'
                            ' (${formatFileSize(task.completedBytes)}'
                            '/${formatFileSize(task.totalBytes)})',
                      ),
                      _SubMono(formatFileSize(task.downloadSpeedBytes)),
                      _offlineBadge(task.status, l10n),
                      _SubMono(
                        task.createdAt == null
                            ? '—'
                            : DateFormat(
                              'MM-dd HH:mm',
                              locale,
                            ).format(task.createdAt!),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _SubAction(
                          label: l10n.filesTaskCancel,
                          destructive: true,
                          onTap:
                              task.canCancel && enabled
                                  ? () => _confirmAndRun(
                                    context,
                                    title: l10n.filesOfflineCancelConfirm,
                                    message: l10n.filesOfflineCancelMessage,
                                    confirmLabel: l10n.filesTaskCancel,
                                    action:
                                        () => controller.cancelOfflineDownload(
                                          task,
                                        ),
                                  )
                                  : null,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        WorkstationPaginationBar(
          currentPage: widget.state.offlineMeta.page,
          totalPages: widget.state.offlineMeta.totalPages,
          totalElements: widget.state.offlineMeta.totalElements,
          rowsPerPage: widget.state.offlineMeta.size,
          busy: widget.state.isBusy,
          onPageChanged: (page) => controller.showOfflineDownloads(page: page),
          onRowsPerPageChanged:
              (size) => controller.showOfflineDownloads(page: 0, size: size),
        ),
      ],
    );
  }

  Widget _offlineBadge(String status, AppLocalizations l10n) {
    final s = status.toUpperCase();
    if (s == 'COMPLETED') {
      return _StatusBadge(l10n.filesStatusCompleted, tone: _BadgeTone.good);
    }
    if (s == 'FAILED') {
      return _StatusBadge(l10n.filesStatusFailed, tone: _BadgeTone.bad);
    }
    if (s == 'RUNNING' || s == 'DOWNLOADING') {
      return _StatusBadge(l10n.filesStatusDownloading, tone: _BadgeTone.good);
    }
    return _StatusBadge(status, tone: _BadgeTone.neutral);
  }
}

// ───────────────────────── 外部存储（10） ─────────────────────────

class _ExternalStorageWorkspace extends ConsumerWidget {
  const _ExternalStorageWorkspace({required this.state});

  final FileBrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !state.isBusy;
    final browsing = state.externalBrowseAccountId != null;
    if (browsing) {
      return _ExternalBrowsePanel(state: state);
    }
    final accounts = state.externalAccounts;
    final ready = accounts.where((a) => a.credentialsConfigured).length;
    final abnormal =
        accounts
            .where(
              (a) =>
                  a.status.toUpperCase() != 'CONNECTED' &&
                  a.status.toUpperCase() != 'ACTIVE',
            )
            .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubHeader(
          title: FileManagerSection.externalStorage.labelOf(l10n),
          subtitle: FileManagerSection.externalStorage.descriptionOf(l10n),
          actions: [
            FilesActionButton(
              label: l10n.filesAddMount,
              icon: Icons.add_rounded,
              variant: FilesActionButtonVariant.primary,
              onPressed:
                  enabled
                      ? () => unawaited(
                        _addExternalStorage(
                          context: context,
                          ref: ref,
                          controller: controller,
                        ),
                      )
                      : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SubMetricStrip(
          cards: [
            _MetricCard(
              label: l10n.filesMetricMounts,
              value: accounts.length.toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.onSurface,
            ),
            _MetricCard(
              label: l10n.filesMetricReady,
              value: ready.toString(),
              detail: l10n.filesCurrentView,
              color: FilesWorkstationPalette.emerald,
            ),
            _MetricCard(
              label: l10n.filesMetricAbnormal,
              value: abnormal.toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.error,
            ),
            _MetricCard(
              label: l10n.filesExternalStorage,
              value: accounts.toSet().map((a) => a.provider).length.toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.onSurface,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 920 ? 2 : 1;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final account in accounts)
                      SizedBox(
                        width:
                            (constraints.maxWidth - (columns - 1) * 12) /
                            columns,
                        child: _ExternalMountCard(
                          account: account,
                          enabled: enabled,
                          onBrowse:
                              () => unawaited(
                                _runFileAction(
                                  context,
                                  () => controller.browseExternalStorage(
                                    account.id,
                                  ),
                                ),
                              ),
                          onTest:
                              () => unawaited(
                                _runFileAction(
                                  context,
                                  () =>
                                      controller.testExternalStorageConnection(
                                        account.id,
                                      ),
                                ),
                              ),
                          onConfig:
                              () => _showExternalStorageDialog(
                                context: context,
                                ref: ref,
                                account: account,
                                onSubmit: ({
                                  required String provider,
                                  required String displayName,
                                  required String encryptedCredentials,
                                }) async {
                                  await controller.updateExternalStorage(
                                    accountId: account.id,
                                    displayName: displayName,
                                    encryptedCredentials: encryptedCredentials,
                                  );
                                  return account;
                                },
                              ),
                          onUnmount:
                              () => _confirmAndRun(
                                context,
                                title: l10n.filesDisableMountConfirm,
                                message: l10n.filesDisableMountMessage(
                                  account.displayName,
                                ),
                                confirmLabel: l10n.filesDisableMount,
                                action:
                                    () => controller.disableExternalStorage(
                                      account,
                                    ),
                              ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ExternalMountCard extends StatelessWidget {
  const _ExternalMountCard({
    required this.account,
    required this.enabled,
    required this.onBrowse,
    required this.onTest,
    required this.onConfig,
    required this.onUnmount,
  });

  final ExternalStorageAccount account;
  final bool enabled;
  final VoidCallback onBrowse;
  final VoidCallback onTest;
  final VoidCallback onConfig;
  final VoidCallback onUnmount;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    final l10n = AppLocalizations.of(context);
    final healthy =
        account.status.toUpperCase() == 'CONNECTED' ||
        account.status.toUpperCase() == 'ACTIVE';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cloud_queue_rounded,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  account.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(
                account.provider.toUpperCase(),
                tone: _BadgeTone.neutral,
              ),
              const SizedBox(width: 6),
              _StatusBadge(
                healthy ? 'ONLINE' : account.status,
                tone: healthy ? _BadgeTone.good : _BadgeTone.bad,
              ),
            ],
          ),
          if (account.lastErrorCode != null) ...[
            const SizedBox(height: 8),
            Text(
              account.lastErrorCode!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTypography.labelSmall,
                color: colors.error,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SubAction(
                  label: l10n.filesOpBrowse,
                  onTap: enabled ? onBrowse : null,
                ),
              ),
              const SizedBox(width: 6),
              _SubAction(
                label: l10n.filesTestConnection,
                onTap: enabled ? onTest : null,
              ),
              const SizedBox(width: 6),
              _SubAction(
                label: l10n.filesOpConfig,
                onTap: enabled ? onConfig : null,
              ),
              const SizedBox(width: 6),
              _SubAction(
                label: l10n.filesOpUnmount,
                destructive: true,
                onTap: enabled ? onUnmount : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── 导入任务（11） ─────────────────────────

class _ImportTasksWorkspace extends ConsumerStatefulWidget {
  const _ImportTasksWorkspace({required this.state});

  final FileBrowserState state;

  @override
  ConsumerState<_ImportTasksWorkspace> createState() =>
      _ImportTasksWorkspaceState();
}

class _ImportTasksWorkspaceState extends ConsumerState<_ImportTasksWorkspace> {
  String _filter = 'ALL';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    final enabled = !widget.state.isBusy;
    final tasks = widget.state.importTasks;
    int countOf(String status) =>
        tasks.where((t) => t.status.toUpperCase() == status).length;
    final running = countOf('RUNNING');
    final completed = countOf('COMPLETED');
    final failed = countOf('FAILED');
    final filtered =
        tasks
            .where((t) => _filter == 'ALL' || t.status.toUpperCase() == _filter)
            .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubHeader(
          title: FileManagerSection.importTasks.labelOf(l10n),
          subtitle: FileManagerSection.importTasks.descriptionOf(l10n),
        ),
        const SizedBox(height: 16),
        _SubMetricStrip(
          cards: [
            _MetricCard(
              label: l10n.filesMetricUploading,
              value: running.toString(),
              detail: l10n.filesCurrentView,
              color: FilesWorkstationPalette.emerald,
            ),
            _MetricCard(
              label: l10n.filesMetricQueued,
              value: countOf('PENDING').toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.onSurface,
            ),
            _MetricCard(
              label: l10n.filesMetricCompleted,
              value: completed.toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.onSurface,
            ),
            _MetricCard(
              label: l10n.filesMetricFailed,
              value: failed.toString(),
              detail: l10n.filesCurrentView,
              color: context.filesColors.error,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SubChipsBar(
          chips: [
            _SubChip(
              label: '${l10n.filesStatusFilterAll} (${tasks.length})',
              active: _filter == 'ALL',
              onTap: () => setState(() => _filter = 'ALL'),
            ),
            _SubChip(
              label: l10n.filesStatusRunning,
              active: _filter == 'RUNNING',
              onTap: () => setState(() => _filter = 'RUNNING'),
            ),
            _SubChip(
              label: l10n.filesStatusCompleted,
              active: _filter == 'COMPLETED',
              onTap: () => setState(() => _filter = 'COMPLETED'),
            ),
            _SubChip(
              label: l10n.filesStatusFailed,
              active: _filter == 'FAILED',
              onTap: () => setState(() => _filter = 'FAILED'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: _SubTable(
              columns: [
                _SubColumn(l10n.filesTaskSource, flex: 3),
                _SubColumn(l10n.filesColumnType, width: 84),
                _SubColumn(l10n.filesColumnSize, width: 96),
                _SubColumn(l10n.filesProgress, flex: 2),
                _SubColumn(l10n.filesImportFileCount, width: 96),
                _SubColumn(l10n.filesOfflineSpeed, width: 100),
                _SubColumn(l10n.filesColumnStatus, width: 88),
                _SubColumn(l10n.filesColumnCreatedAt, width: 108),
                _SubColumn(l10n.filesFileActions, width: 132),
              ],
              rows: [
                for (final task in filtered)
                  _SubRow(
                    cells: [
                      // 失败任务把错误摘要提到次行：仅靠徽章无法解释失败原因。
                      _SubNameCell(
                        name: task.fileName ?? task.sourcePath,
                        detail:
                            (task.errorSummary ?? '').isNotEmpty
                                ? task.errorSummary!
                                : task.sourcePath,
                        isFolder: task.isDirectory,
                      ),
                      _SubMono(task.isDirectory ? 'DIRECTORY' : 'FILE'),
                      _SubMono(formatFileSize(task.totalBytes)),
                      _SubProgressCell(
                        value: task.progress,
                        label:
                            '${(task.progress * 100).toStringAsFixed(1)}%'
                            '${task.totalFiles > 0 ? ' (${task.completedFiles}/${task.totalFiles})' : ''}',
                      ),
                      _SubMono(
                        task.totalFiles > 0
                            ? '${task.completedFiles}/${task.totalFiles}'
                            : '—',
                      ),
                      _SubMono(formatFileSize(task.speedBytes)),
                      _importBadge(task.status, l10n),
                      _SubMono(
                        task.createdAt == null
                            ? '—'
                            : DateFormat(
                              'MM-dd HH:mm',
                              locale,
                            ).format(task.createdAt!),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (task.canCancel)
                              _SubAction(
                                label: l10n.filesTaskCancel,
                                destructive: true,
                                onTap:
                                    enabled
                                        ? () => _confirmAndRun(
                                          context,
                                          title: l10n.filesImportCancelConfirm,
                                          message:
                                              l10n.filesImportCancelMessage,
                                          confirmLabel: l10n.filesTaskCancel,
                                          action:
                                              () => controller.cancelImportTask(
                                                task,
                                              ),
                                        )
                                        : null,
                              ),
                            const SizedBox(width: 6),
                            _SubAction(
                              label: l10n.filesDeleteTask,
                              onTap:
                                  enabled
                                      ? () => _confirmAndRun(
                                        context,
                                        title: l10n.filesDeleteUploadTask,
                                        message:
                                            l10n.filesDeleteUploadTaskMessage,
                                        confirmLabel: l10n.filesDeleteTask,
                                        action:
                                            () => controller.deleteImportTask(
                                              task,
                                            ),
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
          currentPage: widget.state.importMeta.page,
          totalPages: widget.state.importMeta.totalPages,
          totalElements: widget.state.importMeta.totalElements,
          rowsPerPage: widget.state.importMeta.size,
          busy: widget.state.isBusy,
          onPageChanged: (page) => controller.showImportTasks(page: page),
          onRowsPerPageChanged:
              (size) => controller.showImportTasks(page: 0, size: size),
        ),
      ],
    );
  }

  Widget _importBadge(String status, AppLocalizations l10n) {
    final s = status.toUpperCase();
    if (s == 'COMPLETED') {
      return _StatusBadge(l10n.filesStatusCompleted, tone: _BadgeTone.good);
    }
    if (s == 'FAILED') {
      return _StatusBadge(l10n.filesStatusFailed, tone: _BadgeTone.bad);
    }
    if (s == 'RUNNING') {
      return _StatusBadge(l10n.filesStatusRunning, tone: _BadgeTone.good);
    }
    return _StatusBadge(status, tone: _BadgeTone.neutral);
  }
}
