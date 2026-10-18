import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/errors/error_code_l10n.dart';
import 'package:omninest/core/utils/clipboard_writer.dart';
import 'package:omninest/core/utils/download_url_opener.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/core/utils/route_exit.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/files/application/public_share_service.dart';
import 'package:omninest/features/files/domain/public_share.dart';
import 'package:omninest/features/files/presentation/widgets/files_dialog.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';

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
  List<_ShareFolderCrumb> _trail = const [];
  List<ShareChild> _children = const [];
  int _childTotal = 0;
  bool _childrenLoading = false;
  String? _childrenError;

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
      _trail = const [];
      _children = const [];
      _childTotal = 0;
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

    if (_preview?.resourceType == 'FOLDER' && !_needPassword) {
      await _loadChildren(null);
    }
  }

  /// 逐级读取分享子树；服务端只放行根目录之下的节点，越界一律按不存在处理。
  Future<void> _loadChildren(String? parentId) async {
    setState(() {
      _childrenLoading = true;
      _childrenError = null;
    });

    final result = await _service.listChildren(
      widget.token,
      parentId: parentId,
    );

    if (!mounted) return;
    setState(() {
      _childrenLoading = false;
      switch (result) {
        case ShareChildrenSuccess(:final items, :final total):
          _children = items;
          _childTotal = total;
        case ShareChildrenFailure(:final message):
          _children = const [];
          _childTotal = 0;
          _childrenError = message;
      }
    });
  }

  String? get _currentFolderId => _trail.isEmpty ? null : _trail.last.id;

  Future<void> _descend(ShareChild folder) async {
    setState(() {
      _trail = [..._trail, _ShareFolderCrumb(folder.id, folder.name)];
    });
    await _loadChildren(folder.id);
  }

  Future<void> _ascend() async {
    if (_trail.isEmpty) return;
    setState(() {
      _trail = _trail.sublist(0, _trail.length - 1);
    });
    await _loadChildren(_currentFolderId);
  }

  Future<void> _openChild(ShareChild child) async {
    final l10n = AppLocalizations.of(context);
    final url = child.downloadUrl;
    if (url == null || url.isEmpty) {
      return;
    }
    // 与文件页同一口径：Web 直接开新标签，桌面与移动退回复制链接。
    if (openDownloadUrl(url)) {
      if (!mounted) return;
      showOmniFeedback(
        context,
        l10n.filesDownloadOpened,
        severity: OmniFeedbackSeverity.success,
      );
      return;
    }
    final copied = await copyTextToClipboard(url);
    if (!mounted) return;
    showOmniFeedback(
      context,
      copied ? l10n.filesDownloadLinkCopied : l10n.clipboardCopyFailed,
      severity:
          copied ? OmniFeedbackSeverity.success : OmniFeedbackSeverity.error,
    );
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
      // 密码不进 URL：地址栏/历史/收藏不得留存分享口令，登录回跳后由用户重输
      final redirect = Uri(path: '/s/${widget.token}').toString();
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
        showOmniFeedback(
          context,
          AppLocalizations.of(context).filesSavedToMyFiles,
          severity: OmniFeedbackSeverity.success,
        );
        context.go('/files');
      case ShareAcceptDuplicate(:final message):
        showFilesDialog<void>(
          context: context,
          builder:
              (ctx) => FilesDialogFrame(
                title: AppLocalizations.of(context).filesFileExists,
                body: Text(
                  AppLocalizations.of(
                    context,
                  ).messageForErrorCode(message, fallback: message),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(AppLocalizations.of(context).filesGotIt),
                  ),
                ],
              ),
        );
      case ShareAcceptError(:final message):
        showOmniFeedback(
          context,
          AppLocalizations.of(context).filesSaveFailed(
            AppLocalizations.of(
              context,
            ).messageForErrorCode(message, fallback: message),
          ),
          severity: OmniFeedbackSeverity.error,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.filesColors.surface,
      // 本页挂在应用壳层之外：刘海/横屏会切到卡片，同时路由本身没有
      // 任何返回入口，访客直达链接后会被困在此页。
      body: SafeArea(
        child: Column(
          children: [_buildTopBar(context), Expanded(child: _buildBody())],
        ),
      ),
    );
  }

  /// 顶部逃生控件：48dp 返回键，栈内 pop、直达链接兜底回门户。
  Widget _buildTopBar(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: IconButton(
          tooltip: AppLocalizations.of(context).coreBackToPortal,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => exitDetailRoute(context, fallbackRoute: '/portal'),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const AppLoading();

    if (_error != null) {
      return _buildErrorView(
        AppLocalizations.of(
          context,
        ).messageForErrorCode(_error!, fallback: _error),
      );
    }

    if (_needPassword) {
      return _PasswordPrompt(
        initialPassword: _password,
        onSubmit: _onPasswordSubmit,
      );
    }

    if (_preview == null) return const SizedBox.shrink();

    if (_preview!.resourceType == 'FOLDER') {
      return _buildFolderView(context);
    }

    return _PreviewCard(
      preview: _preview!,
      saving: _saving,
      onAccept: _acceptShare,
    );
  }

  /// 文件夹分享：顶部是面包屑与当前目录，中部是可滚动的子项列表，底部保留整份保存入口。
  Widget _buildFolderView(BuildContext context) {
    return Column(
      children: [
        _buildTrailBar(context),
        Expanded(child: _buildChildList(context)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _SaveToMyFilesButton(saving: _saving, onAccept: _acceptShare),
        ),
      ],
    );
  }

  Widget _buildTrailBar(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentName = _trail.isEmpty ? _preview!.fileName : _trail.last.name;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.filesColors.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          if (_trail.isNotEmpty)
            IconButton(
              tooltip: l10n.coreBack,
              icon: const Icon(Icons.arrow_upward_rounded, size: 20),
              onPressed: _ascend,
            ),
          Expanded(
            child: Text(
              currentName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTypography.titleMedium,
                fontWeight: FontWeight.w700,
                color: context.filesColors.onSurface,
              ),
            ),
          ),
          if (!_childrenLoading && _childrenError == null)
            Text(
              l10n.filesShareItemCount(_childTotal),
              style: TextStyle(
                fontSize: AppTypography.labelMedium,
                color: context.filesColors.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChildList(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_childrenLoading) {
      return const AppLoading();
    }
    if (_childrenError != null) {
      return _buildErrorView(
        l10n.messageForErrorCode(_childrenError!, fallback: _childrenError),
      );
    }
    if (_children.isEmpty) {
      return Center(
        child: Text(
          l10n.filesFolderEmpty,
          style: TextStyle(
            fontSize: AppTypography.bodyMedium,
            color: context.filesColors.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: _children.length,
      itemBuilder:
          (context, index) => _buildChildRow(context, _children[index]),
    );
  }

  Widget _buildChildRow(BuildContext context, ShareChild child) {
    return ListTile(
      onTap: () {
        if (child.isFolder) {
          unawaited(_descend(child));
          return;
        }
        unawaited(_openChild(child));
      },
      leading: Icon(
        child.isFolder
            ? Icons.folder_rounded
            : Icons.insert_drive_file_outlined,
        size: 22,
        color: context.filesColors.primary,
      ),
      title: Text(
        child.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: AppTypography.bodyLarge,
          color: context.filesColors.onSurface,
        ),
      ),
      trailing: Text(
        child.isFolder ? '' : formatFileSize(child.sizeBytes),
        style: TextStyle(
          fontSize: AppTypography.labelMedium,
          color: context.filesColors.onSurfaceVariant,
        ),
      ),
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
          borderRadius: BorderRadius.zero,
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
            // 保存按钮
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
