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
    final isFilled = style == ImportButtonStyle.filledButton;
    final Color color = switch (style) {
      ImportButtonStyle.iconButton => rc.onSurfaceVariant,
      ImportButtonStyle.filledButton => rc.surface,
      ImportButtonStyle.outlinedButton => rc.onSurface,
      ImportButtonStyle.textButton => rc.onSurface,
    };
    final button = MediaImportButton(
      subsystemDirectory: 'Reader',
      acceptedExtensions: const ['epub', 'txt', 'cbz', 'zip', 'pdf'],
      reuseExistingFiles: true,
      onFilesPicked: (files, spaceType) {
        ref
            .read(readerImportQueueProvider.notifier)
            .enqueue(files, spaceType: spaceType);
      },
      onImportComplete: () {
        ref.read(readerCenterControllerProvider.notifier).refresh();
      },
      style: style,
      color: color,
      label: label,
    );
    return SizedBox(
      width: isIcon ? 40 : null,
      height: isIcon ? 40 : null,
      child: isFilled ? _withReaderFilledColors(context, rc, button) : button,
    );
  }

  /// 只覆盖填充按钮配色，必须保留主题圆角/内边距/高度。
  ///
  /// 直接 `copyWith(filledButtonTheme: styleFrom(...))` 会整段替换主题
  /// 按钮样式，丢失 `roundedShape` 后回退到 Material 默认胶囊形。
  Widget _withReaderFilledColors(
    BuildContext context,
    ReaderColors rc,
    Widget child,
  ) {
    final theme = Theme.of(context);
    final baseStyle = theme.filledButtonTheme.style ?? FilledButton.styleFrom();
    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: baseStyle.copyWith(
            backgroundColor: WidgetStatePropertyAll(rc.primary),
            foregroundColor: WidgetStatePropertyAll(rc.surface),
          ),
        ),
      ),
      child: child,
    );
  }
}
