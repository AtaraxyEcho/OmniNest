import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/core/errors/error_code_l10n.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';
import 'package:omninest/core/utils/clipboard_writer.dart';
import 'package:omninest/core/utils/download_url_opener.dart';
import 'package:omninest/core/utils/file_saver.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/files/application/shared_folder_browse_controller.dart';
import 'package:omninest/features/files/domain/public_share.dart';
import 'package:omninest/features/files/presentation/widgets/files_dialog.dart';

/// 打开定向分享文件夹的浏览对话框。
///
/// 接收人没有分享明文 token，只能按分享标识走鉴权链；服务端把可见范围
/// 钉在该分享根目录的子树内，因此这里不提供搜索，只允许逐级进入与返回。
Future<void> showSharedFolderBrowser(
  BuildContext context, {
  required String shareId,
  required String folderName,
}) {
  return showFilesDialog<void>(
    context: context,
    builder:
        (dialogContext) => FilesDialogFrame(
          title: folderName,
          width: 520,
          body: SizedBox(
            height: 360,
            child: SharedFolderBrowser(shareId: shareId),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(AppLocalizations.of(dialogContext).coreClose),
            ),
          ],
        ),
  );
}

/// 定向分享文件夹的浏览面板。
class SharedFolderBrowser extends ConsumerStatefulWidget {
  const SharedFolderBrowser({required this.shareId, super.key});

  final String shareId;

  @override
  ConsumerState<SharedFolderBrowser> createState() =>
      _SharedFolderBrowserState();
}

class _SharedFolderBrowserState extends ConsumerState<SharedFolderBrowser> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        ref.read(sharedFolderBrowseProvider.notifier).open(widget.shareId),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final browseState = ref.watch(sharedFolderBrowseProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context, browseState),
        Expanded(child: _buildBody(context, browseState)),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AsyncValue<SharedFolderBrowse?> state,
  ) {
    final l10n = AppLocalizations.of(context);
    final trail = state.asData?.value?.trail ?? const <ShareChild>[];
    final total = state.asData?.value?.page.totalElements ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (trail.isNotEmpty)
            IconButton(
              tooltip: l10n.coreBack,
              icon: const Icon(Icons.arrow_upward_rounded, size: 20),
              onPressed:
                  () => ref.read(sharedFolderBrowseProvider.notifier).ascend(),
            ),
          Expanded(
            child: Text(
              trail.isEmpty ? l10n.filesSharedFolderRoot : trail.last.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTypography.bodyLarge,
                color: context.filesColors.onSurfaceVariant,
              ),
            ),
          ),
          if (!state.isLoading && state.hasValue)
            Text(
              l10n.filesShareItemCount(total),
              style: TextStyle(
                fontSize: AppTypography.labelMedium,
                color: context.filesColors.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<SharedFolderBrowse?> state,
  ) {
    final l10n = AppLocalizations.of(context);
    if (state.isLoading) {
      return const AppLoading();
    }
    if (state.hasError) {
      final message = l10n.messageForErrorCode(
        '${state.error}',
        fallback: '${state.error}',
      );
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppTypography.bodyMedium,
                color: context.filesColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed:
                  () => ref.read(sharedFolderBrowseProvider.notifier).retry(),
              child: Text(l10n.filesRetry),
            ),
          ],
        ),
      );
    }
    final items = state.asData?.value?.page.items ?? const <ShareChild>[];
    if (items.isEmpty) {
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
      itemCount: items.length,
      itemBuilder: (context, index) => _buildRow(context, items[index]),
    );
  }

  Widget _buildRow(BuildContext context, ShareChild child) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      onTap: () => _activate(child),
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
        child.isFolder ? l10n.filesFolder : formatFileSize(child.sizeBytes),
        style: TextStyle(
          fontSize: AppTypography.labelMedium,
          color: context.filesColors.onSurfaceVariant,
        ),
      ),
    );
  }

  void _activate(ShareChild child) {
    if (child.isFolder) {
      unawaited(ref.read(sharedFolderBrowseProvider.notifier).descend(child));
      return;
    }
    unawaited(_openFile(child));
  }

  Future<void> _openFile(ShareChild child) async {
    final l10n = AppLocalizations.of(context);
    final url = child.downloadUrl;
    if (url == null || url.isEmpty) {
      if (!mounted) {
        return;
      }
      showOmniFeedback(
        context,
        l10n.filesDownloadFailed,
        severity: OmniFeedbackSeverity.error,
      );
      return;
    }
    if (kIsWeb) {
      if (openDownloadUrl(url)) {
        if (!mounted) {
          return;
        }
        showOmniFeedback(
          context,
          l10n.filesDownloadOpened,
          severity: OmniFeedbackSeverity.success,
        );
        return;
      }
      final copied = await copyTextToClipboard(url);
      if (!mounted) {
        return;
      }
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
        fileName: child.name,
        sizeBytes: child.sizeBytes,
      );
      if (!mounted || result is LocalFileSaveCancelled) {
        return;
      }
      showOmniFeedback(
        context,
        l10n.filesDownloadSaved,
        severity: OmniFeedbackSeverity.success,
      );
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      showOmniFeedback(
        context,
        '${l10n.filesDownloadFailed}: $error',
        severity: OmniFeedbackSeverity.error,
      );
    }
  }
}
