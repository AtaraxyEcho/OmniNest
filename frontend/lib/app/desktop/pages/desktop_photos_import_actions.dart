part of 'desktop_photos_page.dart';

extension _DesktopPhotosImportActions on _DesktopPhotosPageState {
  Widget _importAction(BuildContext context, AppLocalizations l10n) {
    final appContainer = ProviderScope.containerOf(context, listen: false);
    bool isCurrentSession(int epoch) =>
        appContainer.read(sessionEpochProvider) == epoch;

    void refreshVisibleData() {
      appContainer.invalidate(photoDashboardProvider);
      appContainer.invalidate(photoListProvider);
      appContainer.invalidate(photoFavoritesProvider);
      appContainer.invalidate(photoAlbumsProvider);
    }

    Future<MediaImportCompletionState?> completeImport(
      MediaImportBatchResult result, {
      required int sessionEpoch,
    }) async {
      if (!isCurrentSession(sessionEpoch)) return null;
      if (result.imported.isEmpty) {
        return result.failures.isEmpty
            ? MediaImportCompletionState.completed
            : MediaImportCompletionState.failed;
      }
      final controller = appContainer.read(
        photoCenterControllerProvider.notifier,
      );
      final visible = await controller.refreshAfterImport(
        expectedFileIds: result.imported.map((file) => file.fileNodeId),
        taskIds:
            result.imported
                .map((file) => file.mediaAutoImportTaskId)
                .whereType<String>(),
      );
      if (!isCurrentSession(sessionEpoch)) return null;
      refreshVisibleData();
      final failure = controller.lastImportNotice;
      if (!visible && failure != null && mounted && context.mounted) {
        showDesktopToast(
          context,
          photoImportNoticeText(l10n, failure),
          kind: DesktopToastKind.warn,
        );
        return MediaImportCompletionState.failed;
      }
      return visible
          ? MediaImportCompletionState.completed
          : MediaImportCompletionState.processing;
    }

    return MediaImportButton(
      key: _mediaImportKey,
      subsystemDirectory: 'Photos',
      allowSharedSpace: false,
      reuseExistingFiles: true,
      acceptedExtensions: const <String>[
        'jpg',
        'jpeg',
        'png',
        'gif',
        'heic',
        'heif',
        'bmp',
        'tif',
        'tiff',
        'cr2',
        'nef',
        'arw',
        'dng',
        'mp4',
        'mkv',
        'webm',
        'mov',
        'm4v',
        'avi',
        'flv',
        'wmv',
        'ts',
        'm2ts',
      ],
      label: l10n.filesImport,
      onPressedOverride: () => unawaited(_openImportDialog(context, l10n)),
      buttonBuilder:
          (context, {required onPressed, required busy}) => DesktopButton(
            label: l10n.filesImport,
            icon: DesktopIcons.download,
            variant: DesktopButtonVariant.soft,
            onPressed: onPressed,
            busy: busy,
          ),
      onFilesPicked: (files, spaceType) {
        final importSessionEpoch = appContainer.read(sessionEpochProvider);
        ref
            .read(mediaImportQueueProvider.notifier)
            .enqueue(
              files: files,
              directoryName: 'Photos',
              spaceType: spaceType,
              reuseExistingFiles: true,
              titleForFile:
                  (file) =>
                      '${l10n.desktopMediaImportTaskPhotos} · ${file.name}',
              onComplete: (result) async {
                final completion = await completeImport(
                  result,
                  sessionEpoch: importSessionEpoch,
                );
                if (!isCurrentSession(importSessionEpoch) ||
                    !mounted ||
                    !context.mounted) {
                  return;
                }
                if (result.failures.isNotEmpty ||
                    completion == MediaImportCompletionState.failed) {
                  showDesktopToast(
                    context,
                    l10n.importFailed,
                    kind: DesktopToastKind.warn,
                  );
                } else if (completion ==
                    MediaImportCompletionState.processing) {
                  showDesktopToast(
                    context,
                    l10n.importProcessing(result.imported.length),
                    icon: DesktopIcons.download,
                    actionLabel: l10n.desktopBackgroundTasks,
                    onAction:
                        () => appContainer
                            .read(desktopShellProvider.notifier)
                            .setPanel(DesktopPanel.tasks),
                  );
                } else if (completion == MediaImportCompletionState.completed) {
                  showDesktopToast(
                    context,
                    l10n.importComplete(result.imported.length),
                    icon: DesktopIcons.check,
                  );
                }
              },
            );
        showDesktopToast(
          context,
          l10n.desktopMediaImportQueued(files.length),
          icon: DesktopIcons.download,
          actionLabel: l10n.desktopViewTasks,
          onAction:
              () => appContainer
                  .read(desktopShellProvider.notifier)
                  .setPanel(DesktopPanel.tasks),
        );
      },
      onImportComplete: refreshVisibleData,
      onImportCompleteWithResult:
          (result) => completeImport(
            result,
            sessionEpoch: appContainer.read(sessionEpochProvider),
          ),
    );
  }

  Future<void> _openImportDialog(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final selection = await showDesktopMediaImportDialog(
      context,
      kind: DesktopMediaImportKind.photos,
    );
    if (!mounted || !context.mounted || selection == null) return;
    if (selection.deviceFiles.isNotEmpty) {
      await _mediaImportKey.currentState?.importFiles(selection.deviceFiles);
      return;
    }
    if (selection.fileNodeIds.isNotEmpty) {
      await _importExistingFiles(context, l10n, selection);
    }
  }

  Future<void> _importExistingFiles(
    BuildContext context,
    AppLocalizations l10n,
    DesktopMediaImportSelection selection,
  ) async {
    try {
      final tasks = await ref
          .read(fileBrowserControllerProvider.notifier)
          .requestMediaImports(
            fileNodeIds: selection.fileNodeIds,
            mediaType: 'PHOTO',
          );
      if (!mounted || !context.mounted) return;
      final controller = ref.read(photoCenterControllerProvider.notifier);
      final visible = await controller.refreshAfterImport(
        expectedFileIds: selection.fileNodeIds,
        taskIds: tasks.map((task) => task.taskId),
      );
      if (!mounted || !context.mounted) return;
      ref.invalidate(photoDashboardProvider);
      ref.invalidate(photoListProvider);
      ref.invalidate(photoFavoritesProvider);
      ref.invalidate(photoAlbumsProvider);
      final failure = controller.lastImportNotice;
      if (!visible && failure != null) {
        showDesktopToast(
          context,
          photoImportNoticeText(l10n, failure),
          kind: DesktopToastKind.warn,
        );
      } else if (visible) {
        showDesktopToast(
          context,
          l10n.importComplete(selection.fileNodeIds.length),
          kind: DesktopToastKind.success,
        );
      } else {
        showDesktopToast(
          context,
          l10n.importProcessing(tasks.length),
          kind: DesktopToastKind.info,
        );
      }
    } on Object catch (error) {
      if (!mounted || !context.mounted) return;
      showDesktopToast(
        context,
        failureToast(l10n, l10n.filesImport, error),
        kind: DesktopToastKind.error,
      );
    }
  }
}
