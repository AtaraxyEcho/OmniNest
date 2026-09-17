import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/features/files/media_import_ui.dart'
    show ImportButtonStyle, MediaImportButton;
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_import_queue_controller.dart';

/// Reader 书库导入入口：顶栏图标、页头图标与空态主按钮共用同一配置。
///
/// 选择文件后进入后台导入队列，不阻塞当前页。
class ReaderLibraryImportAction extends ConsumerWidget {
  const ReaderLibraryImportAction({
    this.style = ImportButtonStyle.iconButton,
    this.label,
    super.key,
  });

  final ImportButtonStyle style;

  /// 按钮文案；不传则使用通用「导入文件」。
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
