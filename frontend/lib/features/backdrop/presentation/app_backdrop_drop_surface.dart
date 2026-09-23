import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_palette.dart';

/// 背景设置面板的系统文件拖放层,把拖入的文件转交给上传入口。
///
/// Web 不启用:desktop_drop 在 Web 侧给出的是 blob: 伪路径,而 `XFile` 没有
/// 分块读取流,拖放上传只能把整个文件读进内存,违背大文件处理约束;
/// Web 继续使用文件选择器的 readStream 通道。
class AppBackdropDropSurface extends StatefulWidget {
  const AppBackdropDropSurface({
    required this.palette,
    required this.busy,
    required this.onFilesDropped,
    required this.child,
    super.key,
  });

  final AppBackdropPalette palette;

  /// 上传进行中或面板不可用时禁用接收。
  final bool busy;
  final Future<void> Function(List<XFile> files) onFilesDropped;
  final Widget child;

  @override
  State<AppBackdropDropSurface> createState() => _AppBackdropDropSurfaceState();
}

class _AppBackdropDropSurfaceState extends State<AppBackdropDropSurface> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DropTarget(
      enable: !isWebPlatform && !widget.busy,
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
          if (_dragging && !widget.busy)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.palette.surfaceContainer.withValues(
                      alpha: 0.94,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: widget.palette.accent, width: 2),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.photo_library_rounded,
                          size: 42,
                          color: widget.palette.accent,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.portalLocalBackdropDropHint,
                          style: TextStyle(
                            color: widget.palette.text,
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
