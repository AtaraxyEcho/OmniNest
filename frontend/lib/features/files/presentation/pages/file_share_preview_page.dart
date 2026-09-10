import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/files/application/public_share_service.dart';
import 'package:omninest/features/files/domain/public_share.dart';

/// 文件分享预览页面（公开，无需登录即可查看）。
class FileSharePreviewPage extends ConsumerStatefulWidget {
  const FileSharePreviewPage({
    required this.token,
    this.initialPassword,
    super.key,
  });

  final String token;
  final String? initialPassword;

  @override
  ConsumerState<FileSharePreviewPage> createState() =>
      _FileSharePreviewPageState();
}

class _FileSharePreviewPageState extends ConsumerState<FileSharePreviewPage> {
  late final PublicShareService _service;
  String? _password;
  bool _needPassword = false;
  SharePreviewSuccess? _preview;
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _password = widget.initialPassword;
    _service = ref.read(publicShareServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadPreview();
    });
  }

  Future<void> _loadPreview() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await _service.preview(widget.token, password: _password);

    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result) {
        case SharePreviewSuccess(:final hasPassword):
          _preview = result;
          _needPassword = false;
          // 如果需要密码但没提供，显示密码输入
          if (hasPassword && _password == null) {
            _needPassword = true;
          }
        case SharePreviewNeedPassword():
          _needPassword = true;
        case SharePreviewError(:final message):
          _error = message;
      }
    });
  }

  Future<void> _onPasswordSubmit(String password) async {
    _password = password;
    await _loadPreview();
  }

  Future<void> _acceptShare() async {
    // 检查登录状态
    final authState = ref.read(authSessionProvider);
    final isAuthenticated = authState.asData?.value.isAuthenticated ?? false;
    if (!isAuthenticated) {
      final redirect =
          Uri(
            path: '/s/${widget.token}',
            queryParameters: {if (_password != null) 'pwd': _password},
          ).toString();
      if (mounted) context.go('/login?redirect=$redirect');
      return;
    }

    setState(() => _saving = true);

    final authToken = ref.read(authSessionStoreProvider).readAccessToken();
    final result = await _service.accept(
      widget.token,
      password: _password,
      authToken: authToken,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    switch (result) {
      case ShareAcceptSuccess():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).filesSavedToMyFiles),
          ),
        );
        context.go('/files');
      case ShareAcceptDuplicate(:final message):
        showDialog<void>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: Text(AppLocalizations.of(context).filesFileExists),
                content: Text(message),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(AppLocalizations.of(context).filesGotIt),
                  ),
                ],
              ),
        );
      case ShareAcceptError(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).filesSaveFailed(message),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.filesColors.surface,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const AppLoading.detail();

    if (_error != null) {
      return _buildErrorView(_error!);
    }

    if (_needPassword) {
      return _PasswordPrompt(
        initialPassword: _password,
        onSubmit: _onPasswordSubmit,
      );
    }

    if (_preview == null) return const SizedBox.shrink();

    return _PreviewCard(
      preview: _preview!,
      saving: _saving,
      onAccept: _acceptShare,
    );
  }

  Widget _buildErrorView(String message) {
    return Center(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        constraints: BoxConstraints(maxWidth: 416),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: context.filesColors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: context.filesColors.error,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).filesShareAccessError,
              style: TextStyle(
                fontSize: AppTypography.titleMedium,
                fontWeight: FontWeight.w700,
                color: context.filesColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.filesColors.onSurfaceVariant,
                fontSize: AppTypography.bodyMedium,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loadPreview,
              child: Text(AppLocalizations.of(context).filesRetry),
            ),
          ],
        ),
      ),
    );
  }
}

/// 密码输入提示。
class _PasswordPrompt extends StatefulWidget {
  const _PasswordPrompt({required this.onSubmit, this.initialPassword});

  final ValueChanged<String> onSubmit;
  final String? initialPassword;

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
          borderRadius: BorderRadius.circular(16),
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
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

/// 预览卡片内容。
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.preview,
    required this.saving,
    required this.onAccept,
  });

  final SharePreviewSuccess preview;
  final bool saving;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        constraints: BoxConstraints(maxWidth: 436),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: context.filesColors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
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
                borderRadius: BorderRadius.circular(16),
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
            // 保存按钮
            SizedBox(
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
            ),
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

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
