import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/features/files/application/file_download_url_provider.dart';
import 'package:omninest/features/files/data/file_providers.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/presentation/widgets/file_node_actions.dart';
import 'package:omninest/features/files/presentation/widgets/file_thumbnail.dart';
import 'package:omninest/features/files/presentation/widgets/files_toolbar_control.dart';
import 'package:omninest/features/files/presentation/theme/files_workstation_theme.dart';

/// 文件属性详情栏（模板形态）：标题行 + 缩略图预览块 + 元数据键值 +
/// 底部固定双操作钮（打开/预览 + 创建分享外链）。
///
/// 宽屏作为常驻并排侧栏，窄屏复用为贴底抽屉内容。
class FileInspectorPanel extends StatelessWidget {
  const FileInspectorPanel({
    required this.file,
    required this.actions,
    required this.onClose,
    super.key,
  });

  final FileNode file;
  final FileNodeActionCallbacks actions;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.filesColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor =
        isDark
            ? FilesWorkstationPalette.outlineDark
            : FilesWorkstationPalette.outlineLight;
    final locale = Localizations.localeOf(context).toString();
    final modified =
        file.updatedAt == null
            ? '—'
            : DateFormat('yyyy-MM-dd HH:mm:ss', locale).format(file.updatedAt!);
    final rows = <(String, String)>[
      (
        l10n.filesColumnSize,
        file.isFolder ? l10n.filesFolder : formatFileSize(file.sizeBytes),
      ),
      (l10n.filesColumnModified, modified),
      (l10n.filesInspectorMime, file.mimeType ?? '—'),
      (l10n.filesInspectorPath, file.normalizedPath),
      (
        l10n.filesInspectorSpace,
        file.spaceType == SpaceType.shared
            ? l10n.importToSharedSpace
            : l10n.importToPersonalSpace,
      ),
      (l10n.filesColumnUploader, file.uploaderName ?? file.uploadedBy ?? '—'),
      (l10n.filesInspectorExactBytes, '${file.sizeBytes} B'),
    ];
    final isFile = !file.isFolder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.filesInspectorTitle,
                  style: TextStyle(
                    fontFamily: AppTypography.monoFamily,
                    fontFamilyFallback: AppTypography.monoFamilyFallback,
                    fontSize: AppTypography.labelSmall,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                  ),
                ),
              ),
              FilesToolbarIconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: Icons.close_rounded,
                onPressed: onClose,
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: colors.outlineVariant),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 168,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 96,
                        height: 96,
                        child: Center(child: _InspectorPreview(file: file)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppTypography.labelSmall,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${file.isFolder ? l10n.filesFolder : formatFileSize(file.sizeBytes)}'
                        '${file.mimeType == null ? '' : ' · ${file.mimeType}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppTypography.labelMicro,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                for (final (label, value) in rows)
                  _InspectorKVRow(
                    label: label,
                    value: value,
                    labelColor: labelColor,
                  ),
                _InspectorResolutionRow(file: file, labelColor: labelColor),
                _InspectorVideoMediaRows(file: file, labelColor: labelColor),
              ],
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: colors.outlineVariant),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilesActionButton(
                label: isFile ? l10n.filesPreview : l10n.filesOpen,
                icon:
                    isFile
                        ? Icons.play_arrow_rounded
                        : Icons.folder_open_outlined,
                variant: FilesActionButtonVariant.primary,
                onPressed:
                    isFile
                        ? () => actions.onPreview?.call(file)
                        : () => actions.onOpen?.call(file),
              ),
              const SizedBox(height: 8),
              FilesActionButton(
                label: l10n.filesShare,
                icon: Icons.share_outlined,
                onPressed:
                    actions.onShare != null && isFile
                        ? () => actions.onShare!(file)
                        : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InspectorKVRow extends StatelessWidget {
  const _InspectorKVRow({
    required this.label,
    required this.value,
    required this.labelColor,
  });

  final String label;
  final String value;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.filesColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: AppTypography.labelMicro,
              letterSpacing: 0.8,
              color: labelColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: AppTypography.labelMedium,
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// 预览块内容：图片文件渲染真实缩略图（直角），其余以语义色类型图标呈现。
class _InspectorPreview extends ConsumerWidget {
  const _InspectorPreview({required this.file});

  final FileNode file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isImage =
        !file.isFolder && (file.mimeType?.startsWith('image/') ?? false);
    if (isImage) {
      return FileThumbnail(
        file: file,
        size: 96,
        borderRadius: BorderRadius.zero,
      );
    }
    final icon = switch (fileCategoryOfNode(file)) {
      FileCategoryLabel.image => Icons.image_outlined,
      FileCategoryLabel.video => Icons.movie_outlined,
      FileCategoryLabel.audio => Icons.audio_file_outlined,
      FileCategoryLabel.document => Icons.description_outlined,
      FileCategoryLabel.novel => Icons.menu_book_outlined,
      FileCategoryLabel.comic => Icons.auto_stories_outlined,
      FileCategoryLabel.archive => Icons.inventory_2_outlined,
      _ =>
        file.isFolder
            ? Icons.folder_outlined
            : Icons.insert_drive_file_outlined,
    };
    final color = switch (fileCategoryOfNode(file)) {
      FileCategoryLabel.image => FilesWorkstationPalette.emerald,
      FileCategoryLabel.video => const Color(0xFF0EA5E9),
      FileCategoryLabel.audio => FilesWorkstationPalette.cyan,
      FileCategoryLabel.document => FilesWorkstationPalette.rose,
      _ =>
        file.isFolder
            ? FilesWorkstationPalette.amber
            : context.filesColors.onSurfaceVariant,
    };
    return Icon(icon, size: 40, color: color);
  }
}

/// 图片分辨率行：仅在图片文件且有可用下载地址时解析，异步解码取宽高；
/// 其余类型不渲染该行。
class _InspectorResolutionRow extends ConsumerWidget {
  const _InspectorResolutionRow({required this.file, required this.labelColor});

  final FileNode file;
  final Color labelColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isImage =
        !file.isFolder && (file.mimeType?.startsWith('image/') ?? false);
    if (!isImage) {
      return const SizedBox.shrink();
    }
    final url = ref.watch(fileDownloadUrlProvider(file.id)).asData?.value;
    if (url == null || url.isEmpty) {
      return const SizedBox.shrink();
    }
    final resolution = ref.watch(_imageResolutionProvider(url));
    return _InspectorKVRow(
      label: AppLocalizations.of(context).filesInspectorResolution,
      value: resolution.asData?.value ?? '…',
      labelColor: labelColor,
    );
  }
}

/// 以图片流首帧尺寸推导分辨率；解码失败返回 null 由调用方隐藏。
final _imageResolutionProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, url) async {
      final completer = Completer<ui.Image>();
      final stream = NetworkImage(url).resolve(const ImageConfiguration());
      stream.addListener(
        ImageStreamListener(
          (info, _) {
            if (!completer.isCompleted) {
              completer.complete(info.image);
            }
          },
          onError: (error, stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
        ),
      );
      try {
        final image = await completer.future;
        return '${image.width} × ${image.height}';
      } on Object {
        return null;
      }
    });

/// 视频媒体行：时长 + 分辨率，来自后端 ffprobe 探测（内容缓存）；
/// 非视频或探测失败不渲染。
class _InspectorVideoMediaRows extends ConsumerWidget {
  const _InspectorVideoMediaRows({
    required this.file,
    required this.labelColor,
  });

  final FileNode file;
  final Color labelColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVideo =
        !file.isFolder && (file.mimeType?.startsWith('video/') ?? false);
    if (!isVideo) {
      return const SizedBox.shrink();
    }
    final info = ref.watch(fileMediaInfoProvider(file.id)).asData?.value;
    if (info == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (info.durationLabel != null)
          _InspectorKVRow(
            label: l10n.filesInspectorDuration,
            value: info.durationLabel!,
            labelColor: labelColor,
          ),
        if (info.width != null && info.height != null)
          _InspectorKVRow(
            label: l10n.filesInspectorResolution,
            value: '${info.width} × ${info.height}',
            labelColor: labelColor,
          ),
      ],
    );
  }
}

/// 文件媒体元数据探测（视频时长/分辨率）；失败静默为 null。
final fileMediaInfoProvider = FutureProvider.autoDispose
    .family<FileMediaInfo?, String>((ref, fileId) async {
      try {
        return await ref.watch(fileRepositoryProvider).mediaInfo(fileId);
      } on Object {
        return null;
      }
    });
