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
      onPressed: () => _showFileCreateActions(context, state, controller),
      child: const Icon(Icons.add_rounded),
    );
  }
}

/// 移动端「新建」底部面板：上传/相机/新文件夹/刷新。
///
/// 首页工具栏与列表态浮动按钮共用；宿主必须位于移动壳层（Files 空间）。
Future<void> _showFileCreateActions(
  BuildContext context,
  FileBrowserState state,
  FileBrowserController controller,
) async {
  final l10n = AppLocalizations.of(context);
  // 面板经根导航器呈现，默认落在壳层 Theme 与 MobileShellScope 之外：
  // 在宿主上下文捕获环境后在面板子树内重放。
  final ambience = MobileSheetAmbience.capture(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final canContribute =
      container.read(userCapabilitiesProvider).canContributeContent;
  final canWrite =
      canContribute &&
      state.section == FileManagerSection.allFiles &&
      !state.isBusy;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor:
        ambience.hosted
            ? context.env.sheetSolid
            : context.filesColors.surfaceContainer,
    // 移动壳层取原型 `.glass-sheet` 顶部 r28；窄窗工位形态保持直角。
    shape:
        ambience.hosted
            ? const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            )
            : const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    // 横屏手机上默认 sheet 高度（9/16 屏高）放不下 6 行操作，列表项会被
    // 裁到不可达；改为可滚动并按屏高上限封顶。
    isScrollControlled: true,
    builder:
        (sheetContext) => ambience.wrap(
          SafeArea(
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _MobileSheetHandle(),
                      const SizedBox(height: 8),
                      _MobileCreateActionRow(
                        icon: Icons.upload_file_rounded,
                        label: l10n.filesUploadFile,
                        enabled: canWrite,
                        onTap:
                            canWrite
                                ? () {
                                  Navigator.of(sheetContext).pop();
                                  _pickAndUploadFiles(context, controller);
                                }
                                : null,
                      ),
                      _MobileCreateActionRow(
                        icon: Icons.photo_camera_rounded,
                        label: l10n.filesCameraTakePhoto,
                        enabled: canWrite,
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
                      _MobileCreateActionRow(
                        icon: Icons.videocam_rounded,
                        label: l10n.filesCameraRecordVideo,
                        enabled: canWrite,
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
                      _MobileCreateActionRow(
                        icon: Icons.create_new_folder_outlined,
                        label: l10n.filesNewFolder,
                        enabled: canWrite,
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
                      _MobileCreateActionRow(
                        icon: Icons.refresh_rounded,
                        label: l10n.filesRefresh,
                        enabled: true,
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
        ),
  );
}

/// 面板把手：原型 `.sheet-handle` 36×4 r3 白 22%；工位形态沿用描边色。
class _MobileSheetHandle extends StatelessWidget {
  const _MobileSheetHandle();

  @override
  Widget build(BuildContext context) {
    final hosted = MobileShellScope.isHosted(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color:
                hosted
                    ? const Color(0x38FFFFFF)
                    : context.filesColors.outlineVariant,
            borderRadius: BorderRadius.circular(hosted ? 3 : 0),
          ),
        ),
      ),
    );
  }
}

/// 原型 `.action-sheet-row`：50 高图标 + 11px 标签 + 发丝分隔线。
class _MobileCreateActionRow extends StatelessWidget {
  const _MobileCreateActionRow({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hosted = MobileShellScope.isHosted(context);
    final foreground =
        enabled
            ? (hosted ? context.env.ink : context.filesColors.onSurface)
            : (hosted
                ? context.env.white46
                : context.filesColors.onSurfaceVariant);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border:
              hosted
                  ? Border(bottom: BorderSide(color: context.env.line07))
                  : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: hosted ? 11 : AppTypography.bodyLarge,
                  fontWeight: hosted ? FontWeight.w500 : FontWeight.normal,
                  color: foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
