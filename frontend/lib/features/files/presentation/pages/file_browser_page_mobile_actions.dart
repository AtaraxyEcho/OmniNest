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
    return FloatingActionButton.small(
      tooltip: AppLocalizations.of(context).portalQuickActions,
      backgroundColor: context.mobileColors.musicAccent,
      foregroundColor: context.mobileColors.pageMask,
      onPressed: () => _showActions(context),
      child: Icon(Icons.add_rounded),
    );
  }

  Future<void> _showActions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canWrite =
        state.section == FileManagerSection.allFiles && !state.isBusy;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.mobileColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (sheetContext) => SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.mobileColors.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
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
                              unawaited(
                                _showNameDialog(
                                  context: context,
                                  title: l10n.filesNewFolder,
                                  actionLabel: l10n.filesCreate,
                                  labelText: l10n.filesFolderName,
                                  onSubmit: controller.createFolder,
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
    );
  }
}
