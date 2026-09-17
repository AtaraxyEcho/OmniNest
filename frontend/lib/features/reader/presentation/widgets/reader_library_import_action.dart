import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/features/files/media_import_ui.dart'
    show ImportButtonStyle, MediaImportButton;
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_import_queue_controller.dart';

/// Shared Reader library import entry (top bar, header, empty-state CTA).
///
/// Picked files go to the background import queue and do not block the page.
class ReaderLibraryImportAction extends ConsumerWidget {
  const ReaderLibraryImportAction({
    this.style = ImportButtonStyle.iconButton,
    this.label,
    super.key,
  });

  final ImportButtonStyle style;

  /// Button label; defaults to the generic "Import files" string.
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rc = context.readerColors;
    final isIcon = style == ImportButtonStyle.iconButton;
    return SizedBox(
      width: isIcon ? 40 : null,
      height: isIcon ? 40 : null,
      child: MediaImportButton(
        subsystemDirectory: 'Reader',
        acceptedExtensions: const ['epub', 'txt', 'cbz', 'zip', 'pdf'],
        reuseExistingFiles: true,
        onFilesPicked: (files) {
          ref.read(readerImportQueueProvider.notifier).enqueue(files);
        },
        onImportComplete: () {
          ref.read(readerCenterControllerProvider.notifier).refresh();
        },
        style: style,
        color: isIcon ? rc.onSurfaceVariant : null,
        label: label,
      ),
    );
  }
}
