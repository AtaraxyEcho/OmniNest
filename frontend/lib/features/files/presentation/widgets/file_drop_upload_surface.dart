import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';

/// 接收桌面文件拖放并转交给现有上传队列。
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

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) => _setDragging(true),
      onDragExited: (_) => _setDragging(false),
      onDragDone: (details) {
        _setDragging(false);
        final files = details.files
            .whereType<DropItemFile>()
            .cast<XFile>()
            .toList(growable: false);
        if (files.isNotEmpty) {
          unawaited(widget.onFilesDropped(files));
        }
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
                    borderRadius: BorderRadius.circular(8),
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
