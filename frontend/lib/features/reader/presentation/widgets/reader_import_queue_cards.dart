import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/reader/application/reader_import_queue_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';

/// 「从设备导入」按钮：选择阅读文件并加入导入队列。
class ImportFromDeviceButton extends ConsumerStatefulWidget {
  const ImportFromDeviceButton({super.key});

  @override
  ConsumerState<ImportFromDeviceButton> createState() =>
      _ImportFromDeviceButtonState();
}

class _ImportFromDeviceButtonState
    extends ConsumerState<ImportFromDeviceButton> {
  Future<void> _pickAndUpload() async {
    final l10n = AppLocalizations.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub', 'txt', 'cbz', 'zip'],
        withData: kIsWeb,
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;
      if (!mounted) return;
      final files = result.files.map(_toUploadFile).whereType<XFile>().toList();
      if (files.isEmpty) throw StateError('No readable files selected');
      ref.read(readerImportQueueProvider.notifier).enqueue(files);
    } on Exception {
      if (mounted) {
        showReaderSnackBar(context, l10n.readerImportFailed);
      }
    }
  }

  XFile? _toUploadFile(PlatformFile file) {
    final fileName = file.name;
    final path = file.path;
    if (path != null && path.isNotEmpty) {
      return XFile(path, name: fileName, mimeType: _mimeTypeFor(fileName));
    }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    return XFile.fromData(
      bytes,
      name: fileName,
      mimeType: _mimeTypeFor(fileName),
    );
  }

  String _mimeTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.epub')) {
      return 'application/epub+zip';
    }
    if (lower.endsWith('.cbz') || lower.endsWith('.zip')) {
      return 'application/zip';
    }
    return 'text/plain';
  }

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    return OutlinedButton.icon(
      onPressed: _pickAndUpload,
      icon: Icon(Icons.upload_file_rounded, size: 18, color: rc.onSurface),
      label: Text(
        AppLocalizations.of(context).readerAddBook,
        style: TextStyle(
          color: rc.onSurface,
          fontSize: AppTypography.bodyMedium,
          height: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: rc.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}

/// 导入队列中的单个上传任务行：文件名 + 状态 + 进度 + 重试/取消。
class ImportJobRow extends ConsumerWidget {
  const ImportJobRow({required this.job, super.key});

  final ReaderImportJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final rc = context.readerColors;
    final failed = job.status == ReaderImportJobStatus.failed;
    final label = switch (job.status) {
      ReaderImportJobStatus.queued => l10n.readerImportQueuedShort,
      ReaderImportJobStatus.uploading => l10n.importUploading,
      ReaderImportJobStatus.registering => l10n.readerImportRegistering,
      ReaderImportJobStatus.failed => l10n.readerImportFailed,
      ReaderImportJobStatus.cancelled => l10n.readerImportCancelled,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: rc.outlineVariant),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: [
          Icon(
            failed ? Icons.error_outline_rounded : Icons.book_outlined,
            size: 20,
            color: failed ? rc.danger : rc.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        job.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: rc.onSurface,
                          fontSize: AppTypography.bodyMedium,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      label,
                      style: TextStyle(
                        color: failed ? rc.danger : rc.onSurfaceVariant,
                        fontSize: AppTypography.labelSmall,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (!failed) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: job.progress > 0 ? job.progress : null,
                      minHeight: 2,
                      backgroundColor: rc.surfaceContainerHigh,
                      color: rc.reading,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (failed)
            IconButton(
              onPressed:
                  () => ref
                      .read(readerImportQueueProvider.notifier)
                      .retry(job.id),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              tooltip: l10n.coreRetry,
            ),
          IconButton(
            onPressed:
                () =>
                    ref.read(readerImportQueueProvider.notifier).cancel(job.id),
            icon: Icon(
              failed ? Icons.close_rounded : Icons.stop_rounded,
              size: 18,
              color: rc.onSurfaceVariant,
            ),
            tooltip: failed ? l10n.coreClose : l10n.readerCancelImport,
          ),
        ],
      ),
    );
  }
}
