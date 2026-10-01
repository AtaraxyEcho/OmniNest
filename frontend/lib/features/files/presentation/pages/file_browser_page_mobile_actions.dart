part of 'file_browser_page.dart';

class _FileMobileCreateButton extends StatelessWidget {
  const _FileMobileCreateButton({
    required this.state,
    required this.controller,
  });

  final FileBrowserState state;
  final FileBrowserController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    return FloatingActionButton.small(
      tooltip: AppLocalizations.of(context).portalQuickActions,
      backgroundColor: colors.onSurface,
      foregroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: colors.selectedBorder),
      ),
      onPressed: () => _showActions(context),
      child: const Icon(Icons.add_rounded),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final canContribute =
        container.read(userCapabilitiesProvider).canContributeContent;
    final canWrite =
        canContribute &&
        state.section == FileManagerSection.allFiles &&
        !state.isBusy;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.filesColors.surfaceContainer,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      // 横屏手机上默认 sheet 高度（9/16 屏高）放不下 6 行操作，列表项会被
      // 裁到不可达；改为可滚动并按屏高上限封顶。
      isScrollControlled: true,
      builder:
          (sheetContext) => SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 2,
                        color: context.filesColors.outlineVariant,
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        enabled: canWrite,
                        leading: Icon(Icons.upload_file_rounded),
                        title: Text(l10n.filesUploadFile),
                        onTap:
                            canWrite
                                ? () {
                                  Navigator.of(sheetContext).pop();
                                  _pickAndUploadFiles(context, controller);
                                }
                                : null,
                      ),
                      ListTile(
                        enabled: canWrite,
                        leading: Icon(Icons.photo_camera_rounded),
                        title: Text(l10n.filesCameraTakePhoto),
                        onTap:
                            canWrite
                                ? () {
                                  Navigator.of(sheetContext).pop();
                                  unawaited(
                                    _pickPhotoFromCamera(context, controller),
                                  );
                                }
                                : null,
                      ),
                      ListTile(
                        enabled: canWrite,
                        leading: Icon(Icons.videocam_rounded),
                        title: Text(l10n.filesCameraRecordVideo),
                        onTap:
                            canWrite
                                ? () {
                                  Navigator.of(sheetContext).pop();
                                  unawaited(
                                    _pickVideoFromCamera(context, controller),
                                  );
                                }
                                : null,
                      ),
                      ListTile(
                        enabled: canWrite,
                        leading: Icon(Icons.create_new_folder_outlined),
                        title: Text(l10n.filesNewFolder),
                        onTap:
                            canWrite
                                ? () {
                                  Navigator.of(sheetContext).pop();
                                  controller.beginFolderCreation(
                                    dedupeFolderName(
                                      l10n.filesNewFolderDefault,
                                      state.files,
                                    ),
                                  );
                                }
                                : null,
                      ),
                      ListTile(
                        leading: Icon(Icons.refresh_rounded),
                        title: Text(l10n.filesRefresh),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          unawaited(
                            _runFileAction(
                              context,
                              () => controller.loadSection(state.section),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
  }
}
