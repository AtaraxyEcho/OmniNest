import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';

/// 歌单编辑器提交的数据。
class MusicDeckPlaylistDraft {
  const MusicDeckPlaylistDraft({
    required this.name,
    this.description,
    this.coverBytes,
    this.coverFileName,
  });

  final String name;
  final String? description;
  final Uint8List? coverBytes;
  final String? coverFileName;
}

/// 管理歌单文字和封面输入状态的编辑对话框。
class MusicDeckCreatePlaylistDialog extends StatefulWidget {
  const MusicDeckCreatePlaylistDialog({
    this.initialName = '',
    this.initialDescription,
    this.initialCoverUrl,
    this.editing = false,
    super.key,
  });

  final String initialName;
  final String? initialDescription;
  final String? initialCoverUrl;
  final bool editing;

  @override
  State<MusicDeckCreatePlaylistDialog> createState() =>
      _MusicDeckCreatePlaylistDialogState();
}

class _MusicDeckCreatePlaylistDialogState
    extends State<MusicDeckCreatePlaylistDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  Uint8List? _coverBytes;
  Uint8List? _coverPreviewBytes;
  String? _coverFileName;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
    _nameController.addListener(_handleNameChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_handleNameChanged);
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _handleNameChanged() {
    setState(() {});
  }

  Future<void> _pickCover() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      return;
    }
    Uint8List? preview;
    try {
      preview = await _downsampleCover(bytes);
    } on Exception {
      // 解码失败时回退原图预览，不影响主流程。
      preview = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _coverBytes = bytes;
      _coverPreviewBytes = preview ?? bytes;
      _coverFileName = file.name;
    });
  }

  /// 将封面降采样为 ≤512px 的缩略字节，仅用于 UI 预览，避免全分辨率解码。
  Future<Uint8List> _downsampleCover(Uint8List source) async {
    final ui.Image decoded = await decodeImageFromList(source);
    try {
      final targetWidth =
          decoded.width > decoded.height
              ? 512
              : (512 * decoded.width / decoded.height).round();
      final targetHeight =
          decoded.height > decoded.width
              ? 512
              : (512 * decoded.height / decoded.width).round();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint =
          Paint()
            ..filterQuality = FilterQuality.medium
            ..isAntiAlias = true;
      final src = Rect.fromLTWH(
        0,
        0,
        decoded.width.toDouble(),
        decoded.height.toDouble(),
      );
      final dst = Rect.fromLTWH(
        0,
        0,
        targetWidth.toDouble(),
        targetHeight.toDouble(),
      );
      canvas.drawImageRect(decoded, src, dst, paint);
      final picture = recorder.endRecording();
      final ui.Image scaled = await picture.toImage(targetWidth, targetHeight);
      try {
        final data = await scaled.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List() ?? source;
      } finally {
        scaled.dispose();
      }
    } finally {
      decoded.dispose();
    }
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      return;
    }
    final description = _descriptionController.text.trim();
    Navigator.of(context).pop(
      MusicDeckPlaylistDraft(
        name: name,
        description: description.isEmpty ? null : description,
        coverBytes: _coverBytes,
        coverFileName: _coverFileName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final compact = MediaQuery.sizeOf(context).width < 620;
    final cover = _buildCoverEditor(context, l10n);
    final fields = _buildFields(l10n);
    final colors = context.musicColors;
    return AlertDialog(
      backgroundColor: colors.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outline),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 16, 0),
      title: Row(
        children: [
          Icon(Icons.queue_music_rounded, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.editing
                  ? l10n.musicEditPlaylist
                  : l10n.musicCreatePlaylist,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: AppTypography.titleLarge,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.close_rounded,
              size: 20,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
      scrollable: true,
      content: SizedBox(
        width: 520,
        child:
            compact
                ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [cover, const SizedBox(height: 18), fields],
                )
                : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 154, child: cover),
                    const SizedBox(width: 22),
                    Expanded(child: fields),
                  ],
                ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 22),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.musicCancel),
        ),
        FilledButton.icon(
          onPressed: _nameController.text.trim().isEmpty ? null : _submit,
          icon: Icon(
            widget.editing ? Icons.check_rounded : Icons.add_rounded,
            size: 18,
          ),
          label: Text(widget.editing ? l10n.musicSave : l10n.musicCreate),
        ),
      ],
    );
  }

  /// 封面解码宽度：以设备像素比放大 154px 渲染盒（约 2 倍），避免大图全分辨率解码。
  int? get _coverCacheWidth {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return (154 * dpr * 2).round().clamp(1, 2048);
  }

  Widget _buildCoverEditor(BuildContext context, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child:
                _coverPreviewBytes != null
                    ? Image.memory(
                      _coverPreviewBytes!,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      cacheWidth: _coverCacheWidth,
                    )
                    : MusicDeckArtwork(
                      title: _nameController.text,
                      imageUrl: widget.initialCoverUrl,
                      icon: Icons.queue_music_rounded,
                      borderRadius: 8,
                    ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _pickCover,
          icon: const Icon(Icons.image_outlined, size: 17),
          label: Text(
            _coverPreviewBytes == null
                ? l10n.musicPlaylistCoverPick
                : l10n.musicPlaylistCoverChange,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _coverFileName ?? l10n.musicPlaylistCoverHint,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.musicColors.onSurfaceVariant,
            fontSize: AppTypography.labelSmall,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildFields(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _nameController,
          autofocus: true,
          maxLength: 120,
          textInputAction: TextInputAction.next,
          style: TextStyle(color: context.musicColors.onSurface),
          decoration: InputDecoration(labelText: l10n.musicPlaylistName),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _descriptionController,
          maxLength: 500,
          minLines: 4,
          maxLines: 6,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          style: TextStyle(color: context.musicColors.onSurface),
          decoration: InputDecoration(
            labelText: l10n.musicPlaylistDescription,
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}
