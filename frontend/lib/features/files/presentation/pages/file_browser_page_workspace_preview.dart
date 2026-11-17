part of 'file_browser_page.dart';

/// 移动/托管端保持全屏页面。
void _openFilePreview(BuildContext context, FileNode file) {
  final desktop =
      MediaQuery.sizeOf(context).width >= 600 &&
      !MobileShellScope.isHosted(context);
  if (!desktop) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => FilePreviewPage(file: file)));
    return;
  }
  unawaited(
    showFilesDialog<void>(
      context: context,
      builder: (dialogContext) => _FilePreviewDialog(file: file),
    ),
  );
}

/// 桌面预览弹窗：86vw×88vh 常规形态与整窗全屏形态间切换；
/// Esc 任何时候直接关闭（播放器不吞键），全屏切换钮常驻右上角。
class _FilePreviewDialog extends StatefulWidget {
  const _FilePreviewDialog({required this.file});

  final FileNode file;

  @override
  State<_FilePreviewDialog> createState() => _FilePreviewDialogState();
}

class _FilePreviewDialogState extends State<_FilePreviewDialog> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    final width = _expanded ? size.width : size.width * 0.86;
    final height = _expanded ? size.height : size.height * 0.88;
    final colors = context.filesColors;
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      // 该弹窗不走 Dialog/AlertDialog，框架不会补模态语义；读屏的「对话框」
      // 播报与 Web 侧 aria-modal 均取自这里的 role。
      role: SemanticsRole.dialog,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape):
              () => Navigator.of(context).pop(),
        },
        child: Focus(
          autofocus: true,
          child: Material(
            color: colors.surfaceContainer,
            child: AnimatedContainer(
              duration: MotionToken.fast,
              width: width,
              height: height,
              decoration: BoxDecoration(
                border:
                    _expanded ? null : Border.all(color: colors.selectedBorder),
              ),
              child: Column(
                children: [
                  // 紧凑头部：名称+大小居左，全屏与关闭钮居右，36px 高，
                  // 取代旧 AppBar（返回钮过大/标题过大/大小与悬浮钮重叠）。
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: colors.outlineVariant),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.file.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: AppTypography.bodyMedium,
                                    fontWeight: FontWeight.w600,
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                formatFileSize(widget.file.sizeBytes),
                                style: TextStyle(
                                  fontFamily: AppTypography.monoFamily,
                                  fontFamilyFallback:
                                      AppTypography.monoFamilyFallback,
                                  fontSize: AppTypography.labelSmall,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilesToolbarIconButton(
                          tooltip:
                              _expanded
                                  ? l10n.filesPreviewExitFullscreen
                                  : l10n.filesPreviewFullscreen,
                          icon:
                              _expanded
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.open_in_full_rounded,
                          onPressed:
                              () => setState(() => _expanded = !_expanded),
                        ),
                        FilesToolbarIconButton(
                          tooltip:
                              MaterialLocalizations.of(
                                context,
                              ).closeButtonTooltip,
                          icon: Icons.close_rounded,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ClipRect(
                      child: FilePreviewPage(file: widget.file, embedded: true),
                    ),
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
