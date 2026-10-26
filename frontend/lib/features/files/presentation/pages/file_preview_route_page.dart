import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/files/application/file_node_providers.dart';
import 'package:omninest/features/files/presentation/pages/file_preview_page.dart';

/// 按文件 ID 打开预览；搜索命中没有完整节点，需要先按 ID 回源。
class FilePreviewRoutePage extends ConsumerWidget {
  const FilePreviewRoutePage({required this.fileId, super.key});

  final String fileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(fileNodeByIdProvider(fileId))
        .when(
          data: (file) => FilePreviewPage(file: file),
          loading: () => const Scaffold(body: AppLoading()),
          error:
              (error, _) => Scaffold(
                body: AppErrorView(
                  message: describeUserFacingError(error, l10n: l10n).message,
                  onRetry: () => ref.invalidate(fileNodeByIdProvider(fileId)),
                  onBack: () => Navigator.of(context).maybePop(),
                ),
              ),
        );
  }
}
