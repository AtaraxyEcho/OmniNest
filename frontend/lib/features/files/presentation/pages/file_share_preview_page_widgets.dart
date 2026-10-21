part of 'file_share_preview_page.dart';

/// 密码输入提示。
class _PasswordPrompt extends StatefulWidget {
  const _PasswordPrompt({
    required this.onSubmit,
    this.initialPassword,
    this.errorText,
  });

  final ValueChanged<String> onSubmit;
  final String? initialPassword;

  /// 提取码被拒绝时的提示文案，为空表示首次要求输入。
  final String? errorText;

  @override
  State<_PasswordPrompt> createState() => _PasswordPromptState();
}

class _PasswordPromptState extends State<_PasswordPrompt> {
  late final TextEditingController _controller;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPassword);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        constraints: BoxConstraints(maxWidth: 396),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: context.filesColors.surfaceContainerHighest,
          borderRadius: BorderRadius.zero,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              color: context.filesColors.primary,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).filesPasswordAccess,
              style: TextStyle(
                color: context.filesColors.onSurface,
                fontSize: AppTypography.titleMedium,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).filesEnterSharePassword,
              style: TextStyle(
                color: context.filesColors.onSurfaceVariant,
                fontSize: AppTypography.bodyMedium,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              obscureText: _obscure,
              autofocus: widget.initialPassword == null,
              style: TextStyle(color: context.filesColors.onSurface),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).filesEnterPassword,
                errorText:
                    widget.errorText == null
                        ? null
                        : AppLocalizations.of(context).messageForErrorCode(
                          widget.errorText!,
                          fallback: widget.errorText,
                        ),
                hintStyle: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                prefixIcon: const Icon(Icons.key_rounded, size: 18),
                suffixIcon: IconButton(
                  tooltip:
                      _obscure
                          ? AppLocalizations.of(context).coreShowPassword
                          : AppLocalizations.of(context).coreHidePassword,
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.zero),
              ),
              onSubmitted: (v) {
                if (v.isNotEmpty) widget.onSubmit(v);
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final text = _controller.text.trim();
                  if (text.isNotEmpty) widget.onSubmit(text);
                },
                child: Text(AppLocalizations.of(context).filesAccess),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 保存到"我的文件"的主操作按钮；文件态与文件夹态共用一份，
/// 避免同一页面出现两处内联转圈。
class _SaveToMyFilesButton extends StatelessWidget {
  const _SaveToMyFilesButton({required this.saving, required this.onAccept});

  final bool saving;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: saving ? null : onAccept,
        icon:
            saving
                ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : const Icon(Icons.save_alt),
        label: Text(AppLocalizations.of(context).filesSaveToMyFiles),
      ),
    );
  }
}

/// 预览卡片内容。
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.preview,
    required this.saving,
    required this.onAccept,
    required this.onDownload,
  });

  final SharePreviewSuccess preview;
  final bool saving;
  final VoidCallback onAccept;

  /// 免登录直接下载：没有系统账号的外部访客也能拿到文件。
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        constraints: BoxConstraints(maxWidth: 436),
        padding: const EdgeInsets.all(32),
        // 工位规范：hairline 边框替代投影。
        decoration: BoxDecoration(
          color: context.filesColors.surfaceContainerHighest,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: context.filesColors.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 文件图标
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.zero,
              ),
              child: Icon(
                _fileIcon(preview.mimeType, preview.resourceType),
                size: 36,
                color: context.filesColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            // 文件名
            Text(
              preview.fileName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTypography.titleLarge,
                fontWeight: FontWeight.w700,
                color: context.filesColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            // 文件信息
            Text(
              _formatSize(preview.sizeBytes),
              style: TextStyle(
                fontSize: AppTypography.bodyLarge,
                color: context.filesColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            // 下载按钮（匿名可用）+ 保存按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: saving ? null : onDownload,
                icon: const Icon(Icons.download_rounded),
                label: Text(AppLocalizations.of(context).filesDownload),
              ),
            ),
            const SizedBox(height: 12),
            _SaveToMyFilesButton(saving: saving, onAccept: onAccept),
            const SizedBox(height: 12),
            Text(
              'Powered by OmniNest',
              style: TextStyle(
                fontSize: AppTypography.labelSmall,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _fileIcon(String? mimeType, String resourceType) {
    if (resourceType == 'FOLDER') return Icons.folder_rounded;
    if (mimeType == null) return Icons.insert_drive_file_outlined;
    if (mimeType.startsWith('image/')) return Icons.image_outlined;
    if (mimeType.startsWith('video/')) return Icons.movie_outlined;
    if (mimeType.startsWith('audio/')) return Icons.music_note_outlined;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (mimeType.contains('zip') || mimeType.contains('archive')) {
      return Icons.archive_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _formatSize(int bytes) => formatFileSize(bytes);
}

/// 访客进入分享子树的路径节点，只保留标识与目录名。
class _ShareFolderCrumb {
  const _ShareFolderCrumb(this.id, this.name);

  final String id;
  final String name;
}
