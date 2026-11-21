import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omninest/app/desktop/desktop_import_filter.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/platform/file_pick.dart';
import 'package:omninest/platform/platform_capabilities.dart';

/// 接收桌面文件及文件夹拖放并递归展开后转交给现有上传队列。
class FileDropUploadSurface extends StatefulWidget {
  const FileDropUploadSurface({
    required this.enabled,
    required this.onFilesDropped,
    required this.child,
    super.key,
  });

  final bool enabled;
  final Future<void> Function(List<XFile> files) onFilesDropped;
  final Widget child;

  @override
  State<FileDropUploadSurface> createState() => _FileDropUploadSurfaceState();
}

class _FileDropUploadSurfaceState extends State<FileDropUploadSurface> {
  bool _dragging = false;

  Future<void> _handleDrop(List<DropItem> droppedItems) async {
    final files = await expandDroppedItems(droppedItems);
    if (!mounted || files.isEmpty) {
      return;
    }
    await widget.onFilesDropped(files);
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformCapabilities.current().supportsDragAndDropUpload) {
      return widget.child;
    }
    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) => _setDragging(true),
      onDragExited: (_) => _setDragging(false),
      onDragDone: (details) {
        _setDragging(false);
        unawaited(_handleDrop(details.files));
      },
      child: Stack(
        children: [
          widget.child,
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.filesColors.surfaceContainerHigh.withValues(
                      alpha: 0.94,
                    ),
                    borderRadius: BorderRadius.zero,
                    border: Border.all(
                      color: context.filesColors.primary,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_upload_outlined,
                          size: 42,
                          color: context.filesColors.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          AppLocalizations.of(context).filesDropToUpload,
                          style: TextStyle(
                            color: context.filesColors.onSurface,
                            fontSize: AppTypography.titleMedium,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _setDragging(bool value) {
    if (!mounted || _dragging == value) {
      return;
    }
    setState(() => _dragging = value);
  }
}
