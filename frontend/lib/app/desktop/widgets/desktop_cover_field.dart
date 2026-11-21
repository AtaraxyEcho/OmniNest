import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/platform/file_pick.dart';

/// 封面展示形态：竖版海报（2:3）或方图封面（1:1）。
enum DesktopCoverFieldShape { poster, square }

/// 本地选中的封面文件快照，供编辑抽屉即时预览与提交上传。
class DesktopPickedCover {
  const DesktopPickedCover({
    required this.bytes,
    required this.fileName,
    this.filePath,
  });

  final Uint8List bytes;
  final String fileName;
  final String? filePath;
}

/// 统一桌面封面更换控件（对齐原型 `metaFields.tsx:27-59`）：
/// 支持 `poster (2:3)` / `square (1:1)`、点击选图本地 `Image.memory` 即时预览、
/// 上传图片 / 使用外链切换、清除封面，以及格式与 `<= 10MB` 校验。
class DesktopCoverField extends StatefulWidget {
  const DesktopCoverField({
    required this.label,
    required this.urlController,
    required this.onPicked,
    required this.onClear,
    this.shape = DesktopCoverFieldShape.poster,
    this.previewUrl,
    this.coverKind = DesktopCoverKind.network,
    this.readerItemId,
    this.fallbackIcon = DesktopIcons.image,
    this.pickedCover,
    this.cleared = false,
    this.urlError,
    this.enabled = true,
    this.allowExternalUrl = true,
    this.maxBytes = defaultMaxBytes,
    this.onUrlChanged,
    super.key,
  });

  static const int defaultMaxBytes = 10 * 1024 * 1024;
  static const List<String> allowedExtensions = <String>[
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
  ];

  final String label;
  final TextEditingController urlController;
  final ValueChanged<DesktopPickedCover> onPicked;
  final VoidCallback onClear;
  final DesktopCoverFieldShape shape;
  final String? previewUrl;
  final DesktopCoverKind coverKind;
  final String? readerItemId;
  final IconData fallbackIcon;
  final DesktopPickedCover? pickedCover;
  final bool cleared;
  final String? urlError;
  final bool enabled;
  final bool allowExternalUrl;
  final int maxBytes;
  final ValueChanged<String>? onUrlChanged;

  @override
  State<DesktopCoverField> createState() => _DesktopCoverFieldState();
}

class _DesktopCoverFieldState extends State<DesktopCoverField> {
  bool _showUrlInput = false;
  bool _picking = false;
  String? _pickError;

  @override
  void initState() {
    super.initState();
    _showUrlInput =
        widget.allowExternalUrl && widget.urlController.text.trim().isNotEmpty;
  }

  @override
  void didUpdateWidget(covariant DesktopCoverField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.allowExternalUrl &&
        widget.urlController.text.trim().isNotEmpty &&
        !_showUrlInput) {
      _showUrlInput = true;
    }
    if (widget.urlError != null && widget.allowExternalUrl) {
      _showUrlInput = true;
    }
  }

  bool get _hasAnyCover {
    if (widget.pickedCover != null) {
      return true;
    }
    if (widget.cleared) {
      return false;
    }
    if (widget.urlController.text.trim().isNotEmpty) {
      return true;
    }
    return (widget.previewUrl ?? '').trim().isNotEmpty;
  }

  Future<void> _pickImage() async {
    if (!widget.enabled || _picking) {
      return;
    }
    setState(() {
      _picking = true;
      _pickError = null;
    });
    try {
      final files = await FilePick.pickImages();
      if (!mounted || files.isEmpty) {
        return;
      }
      final file = files.first;
      final fileName = file.name.trim();
      final ext = _extensionOf(fileName);
      if (!DesktopCoverField.allowedExtensions.contains(ext)) {
        setState(() {
          _pickError = 'JPG / PNG / WebP / GIF';
        });
        return;
      }
      final bytes = await file.readBytes();
      if (!mounted) {
        return;
      }
      if (bytes.isEmpty) {
        setState(() {
          _pickError = 'Empty image file';
        });
        return;
      }
      if (bytes.length > widget.maxBytes) {
        final maxMb = (widget.maxBytes / (1024 * 1024)).round();
        setState(() {
          _pickError = 'Image exceeds ${maxMb}MB limit';
        });
        return;
      }
      setState(() => _pickError = null);
      widget.onPicked(
        DesktopPickedCover(
          bytes: bytes,
          fileName: fileName.isEmpty ? 'cover.$ext' : fileName,
          filePath: file.path,
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() => _pickError = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) {
      return '';
    }
    return fileName.substring(dot + 1).toLowerCase();
  }

  Widget _buildPreview(DesktopSkin skin) {
    final width = widget.shape == DesktopCoverFieldShape.poster ? 92.0 : 108.0;
    final height =
        widget.shape == DesktopCoverFieldShape.poster ? 138.0 : 108.0;
    final radius = BorderRadius.circular(12);

    Widget artwork;
    if (widget.pickedCover != null) {
      artwork = Image.memory(
        widget.pickedCover!.bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    } else if (widget.cleared) {
      artwork = _emptyCoverBox(skin);
    } else {
      final typedUrl = widget.urlController.text.trim();
      final effectiveUrl =
          typedUrl.isNotEmpty ? typedUrl : (widget.previewUrl ?? '').trim();
      if (effectiveUrl.isEmpty) {
        artwork = _emptyCoverBox(skin);
      } else if (typedUrl.isNotEmpty) {
        artwork = DesktopCover(
          url: typedUrl,
          kind: DesktopCoverKind.network,
          fallbackIcon: widget.fallbackIcon,
          cacheWidth: 400,
        );
      } else {
        artwork = DesktopCover(
          url: effectiveUrl,
          kind: widget.coverKind,
          readerItemId: widget.readerItemId,
          fallbackIcon: widget.fallbackIcon,
          cacheWidth: 400,
        );
      }
    }

    return DesktopHover(
      enabled: widget.enabled && !_picking,
      builder:
          (context, hovered) => GestureDetector(
            onTap: widget.enabled && !_picking ? _pickImage : null,
            child: Container(
              width: width,
              height: height,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: skin.raise2,
                borderRadius: radius,
                border: Border.all(
                  color: hovered ? skin.accent : skin.line2,
                  width: hovered ? 1.5 : 1,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  artwork,
                  AnimatedOpacity(
                    duration: MotionToken.reduced(context, MotionToken.fast),
                    opacity: hovered || _picking ? 1 : 0,
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.48),
                      child: Center(
                        child:
                            _picking
                                ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : const Icon(
                                  DesktopIcons.upload,
                                  size: 20,
                                  color: Colors.white,
                                ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _emptyCoverBox(DesktopSkin skin) {
    return ColoredBox(
      color: skin.raise2,
      child: Center(
        child: Icon(widget.fallbackIcon, size: 24, color: skin.text3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final errorMessage = _pickError ?? widget.urlError;
    final maxMb = (widget.maxBytes / (1024 * 1024)).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: DesktopType.dense(
            skin.text2,
          ).copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPreview(skin),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DesktopButton(
                        label: l10n.desktopFilesUpload,
                        icon: DesktopIcons.upload,
                        variant: DesktopButtonVariant.soft,
                        busy: _picking,
                        onPressed: widget.enabled ? _pickImage : null,
                      ),
                      if (widget.allowExternalUrl)
                        DesktopButton(
                          label: l10n.readerLabelCoverUrl,
                          icon: DesktopIcons.link,
                          variant: DesktopButtonVariant.ghost,
                          active: _showUrlInput,
                          onPressed:
                              widget.enabled
                                  ? () => setState(
                                    () => _showUrlInput = !_showUrlInput,
                                  )
                                  : null,
                        ),
                      if (_hasAnyCover)
                        DesktopButton(
                          label: l10n.videoClear,
                          icon: DesktopIcons.close,
                          variant: DesktopButtonVariant.ghost,
                          onPressed:
                              widget.enabled
                                  ? () {
                                    setState(() => _pickError = null);
                                    widget.urlController.clear();
                                    widget.onClear();
                                  }
                                  : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.pickedCover != null
                        ? widget.pickedCover!.fileName
                        : 'JPG / PNG / WebP / GIF · ≤ ${maxMb}MB',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.caption(skin.text3),
                  ),
                  if (_showUrlInput && widget.allowExternalUrl) ...[
                    const SizedBox(height: 10),
                    DesktopTextField(
                      controller: widget.urlController,
                      hint: 'https://...',
                      enabled: widget.enabled,
                      error: widget.urlError,
                      onChanged: (value) {
                        setState(() => _pickError = null);
                        widget.onUrlChanged?.call(value);
                      },
                    ),
                  ],
                  if (errorMessage != null &&
                      (!_showUrlInput || _pickError != null)) ...[
                    const SizedBox(height: 6),
                    Text(
                      errorMessage,
                      style: DesktopType.caption(DesktopPalette.danger),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
