import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'package:omninest/core/utils/file_saver.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/core/utils/route_exit.dart';
import 'package:omninest/core/log/dev_log.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/core/widgets/infinite_scroll.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/application/public_share_service.dart';
import 'package:omninest/features/files/domain/public_share.dart';
import 'package:omninest/features/files/presentation/pages/file_browser_page.dart';
import 'package:omninest/features/files/presentation/widgets/files_dialog.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';

part 'file_share_preview_page_widgets.dart';

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

  /// 提取码被服务端拒绝时的提示；首次要求输入时保持为空。
  String? _passwordError;
  SharePreviewSuccess? _preview;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  List<_ShareFolderCrumb> _trail = const [];
  List<ShareChild> _children = const [];
  int _childTotal = 0;
  int _childPage = 0;
  bool _childHasMore = false;
  bool _childrenLoading = false;
  bool _childrenLoadingMore = false;
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
      _passwordError = null;
      _trail = const [];
      _children = const [];
      _childTotal = 0;
      _childPage = 0;
      _childHasMore = false;
    });

    final result = await _service.preview(widget.token, password: _password);

    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result) {
        case SharePreviewSuccess():
          // 预览成功即代表已通过服务端授权（口令或缓存会话），不能再以
          // “链接带口令”为由要求二次输入。
          _preview = result;
          _needPassword = false;
          _passwordError = null;
        case SharePreviewNeedPassword(:final message):
          _needPassword = true;
          // 已经提交过提取码仍被拒，才把服务端文案当错误显示；
          // 首次要求输入不是错误，否则一进页面就满屏红。
          _passwordError = (_password?.isNotEmpty ?? false) ? message : null;
        case SharePreviewError(:final message):
          _error = message;
      }
    });

    if (_preview?.resourceType == 'FOLDER' && !_needPassword) {
      await _loadChildren(null);
    }

    // 登录回跳后自动完成刚才被登录打断的转存；未登录时保留标记，等用户登录。
    final session = await ref.read(authSessionProvider.future);
    if (!mounted) {
      return;
    }
    if (session.isAuthenticated && _service.takePendingAccept(widget.token)) {
      // 登录回跳的自动转存沿用根目录，避免恢复流程里再弹出目录选择。
      await _acceptShare(askTarget: false);
    }
  }

  /// 逐级读取分享子树；服务端只放行根目录之下的节点，越界一律按不存在处理。
  Future<void> _loadChildren(String? parentId) async {
    setState(() {
      _childrenLoading = true;
      _childrenError = null;
      _children = const [];
      _childPage = 0;
      _childHasMore = false;
    });

    final result = await _service.listChildren(
      widget.token,
      parentId: parentId,
      page: _childPage,
    );

    if (!mounted) return;
    setState(() {
      _childrenLoading = false;
      switch (result) {
        case ShareChildrenSuccess(:final items, :final total):
          _children = items;
          _childTotal = total;
          _childHasMore = items.length < total;
        case ShareChildrenFailure(:final message):
          _children = const [];
          _childTotal = 0;
          _childHasMore = false;
          _childrenError = message;
      }
    });
  }

  /// 触底续页：按已有条目数量取下一页并去重追加，失败静默等下次触底重试。
  Future<void> _loadMoreChildren(String? parentId) async {
    if (_childrenLoading || _childrenLoadingMore || !_childHasMore) {
      return;
    }
    setState(() => _childrenLoadingMore = true);
    final nextPage = _childPage + 1;
    final result = await _service.listChildren(
      widget.token,
      parentId: parentId,
      page: nextPage,
    );
    if (!mounted) return;
    setState(() {
      _childrenLoadingMore = false;
      switch (result) {
        case ShareChildrenSuccess(:final items, :final total):
          final seen = _children.map((child) => child.id).toSet();
          _children = [
            ..._children,
            ...items.where((child) => !seen.contains(child.id)),
          ];
          _childTotal = total;
          _childPage = nextPage;
          _childHasMore = _children.length < total;
        case ShareChildrenFailure(:final message):
          _childrenError = message;
          _childHasMore = false;
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
    final url = child.downloadUrl;
    if (url == null || url.isEmpty) {
      return;
    }
    await _openDownloadUrl(
      url,
      fileName: child.name,
      sizeBytes: child.sizeBytes,
    );
  }

  /// 单文件分享免登录直接下载：后端 `GET /s/{token}` 凭分享会话即可签发地址。
  Future<void> _downloadCurrentFile() async {
    final l10n = AppLocalizations.of(context);
    final preview = _preview;
    if (preview == null) {
      return;
    }
    setState(() => _saving = true);
    final result = await _service.access(widget.token, password: _password);
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case ShareAccessSuccess(:final downloadUrl):
        await _openDownloadUrl(
          downloadUrl,
          fileName: preview.fileName,
          sizeBytes: preview.sizeBytes,
        );
      case ShareAccessFailure(:final message):
        showOmniFeedback(
          context,
          l10n.messageForErrorCode(message, fallback: l10n.filesDownloadFailed),
          severity: OmniFeedbackSeverity.error,
        );
    }
  }

  /// 与文件页同一口径：Web 开新标签，桌面与移动流式落盘。
  Future<void> _openDownloadUrl(
    String url, {
    required String fileName,
    required int sizeBytes,
  }) async {
    final l10n = AppLocalizations.of(context);
    if (kIsWeb) {
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
      return;
    }
    try {
      final result = await saveDownloadUrlToLocalFile(
        url: url,
        fileName: fileName,
        sizeBytes: sizeBytes,
      );
      if (!mounted || result is LocalFileSaveCancelled) return;
      showOmniFeedback(
        context,
        l10n.filesDownloadSaved,
        severity: OmniFeedbackSeverity.success,
      );
    } on Exception catch (error) {
      if (!mounted) return;
      showOmniFeedback(
        context,
        '${l10n.filesDownloadFailed}: $error',
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  Future<void> _onPasswordSubmit(String password) async {
    _password = password;
    await _loadPreview();
  }

  Future<void> _acceptShare({bool askTarget = true}) async {
    // 检查登录状态
    final authState = ref.read(authSessionProvider);
    final isAuthenticated = authState.asData?.value.isAuthenticated ?? false;
    if (!isAuthenticated) {
      // 密码不进 URL：地址栏/历史/收藏不得留存分享口令；已授权的会话令牌
      // 留在 PublicShareService 内存里，登录回跳后直接复用并继续转存。
      _service.markPendingAccept(widget.token);
      final redirect = Uri(path: '/s/${widget.token}').toString();
      if (mounted) context.go('/login?redirect=$redirect');
      return;
    }
    _service.takePendingAccept(widget.token);

    String? targetParentId;
    if (askTarget) {
      targetParentId = await showFilesFolderPickerDialog(context: context);
      if (!mounted || targetParentId == null) {
        return;
      }
    }

    setState(() => _saving = true);

    final result = await _service.accept(
      widget.token,
      password: _password,
      targetParentId: targetParentId,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    switch (result) {
      case ShareAcceptSuccess():
        try {
          // 转存直接写入个人空间，回到文件页前必须重载列表，否则看不到新文件。
          await ref.read(fileBrowserControllerProvider.notifier).showFiles();
        } on Exception catch (error) {
          devLog('转存后刷新文件列表失败: $error');
        }
        if (!mounted) return;
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
        errorText: _passwordError,
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
      onAccept: () => _acceptShare(),
      onDownload: _downloadCurrentFile,
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
          child: _SaveToMyFilesButton(
            saving: _saving,
            onAccept: () => _acceptShare(),
            label:
                _trail.isEmpty
                    ? null
                    : AppLocalizations.of(context).filesSaveWholeSharedFolder,
          ),
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
    return InfiniteScrollTrigger(
      enabled: _childHasMore && !_childrenLoadingMore,
      onLoadMore: () => unawaited(_loadMoreChildren(_currentFolderId)),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: _children.length,
        itemBuilder:
            (context, index) => _buildChildRow(context, _children[index]),
      ),
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
