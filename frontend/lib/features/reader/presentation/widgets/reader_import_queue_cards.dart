import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/reader/application/reader_import_queue_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';

/// 从设备选择阅读文件并加入导入队列的入口卡。
class ImportFromDeviceTile extends ConsumerStatefulWidget {
  const ImportFromDeviceTile({super.key});

  @override
  ConsumerState<ImportFromDeviceTile> createState() =>
      _ImportFromDeviceTileState();
}

class _ImportFromDeviceTileState extends ConsumerState<ImportFromDeviceTile> {
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
    return GestureDetector(
      onTap: _pickAndUpload,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.readerColors.outlineVariant),
                color: context.readerColors.surfaceContainerHighest.withValues(
                  alpha: 0.28,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_rounded,
                    color: context.readerColors.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context).readerAddBook,
                    style: TextStyle(
                      color: context.readerColors.onSurfaceVariant,
                      fontSize: 11,
                      height: 14 / 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).readerAddBook,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.readerColors.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 导入队列中的单个上传任务卡。
class ImportJobCard extends ConsumerWidget {
  const ImportJobCard({required this.job, super.key});

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 2 / 3,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: rc.surfaceContainerHighest,
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    failed ? Icons.error_outline_rounded : Icons.book_outlined,
                    color: failed ? rc.danger : rc.primary,
                    size: 30,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: rc.onSurface,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (!failed)
                    LinearProgressIndicator(
                      value: job.progress > 0 ? job.progress : null,
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    children: [
                      if (failed)
                        IconButton(
                          onPressed:
                              () => ref
                                  .read(readerImportQueueProvider.notifier)
                                  .retry(job.id),
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: l10n.coreRetry,
                        ),
                      IconButton(
                        onPressed:
                            () => ref
                                .read(readerImportQueueProvider.notifier)
                                .cancel(job.id),
                        icon: Icon(
                          failed ? Icons.close_rounded : Icons.stop_rounded,
                        ),
                        tooltip:
                            failed ? l10n.coreClose : l10n.readerCancelImport,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          job.fileName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: rc.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
