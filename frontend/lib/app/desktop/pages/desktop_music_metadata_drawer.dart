import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover_field.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/platform/file_pick.dart';
import 'package:omninest/features/music/music_portal.dart';

Future<bool?> showDesktopMusicMetadataDrawer({
  required BuildContext context,
  required MusicTrack track,
}) {
  return showDesktopDrawer<bool>(
    context,
    width: 500,
    barrierDismissible: true,
    builder: (_) => _DesktopMusicMetadataDrawer(track: track),
  );
}

class _DesktopMusicMetadataDrawer extends ConsumerStatefulWidget {
  const _DesktopMusicMetadataDrawer({required this.track});

  final MusicTrack track;

  @override
  ConsumerState<_DesktopMusicMetadataDrawer> createState() =>
      _DesktopMusicMetadataDrawerState();
}

class _DesktopMusicMetadataDrawerState
    extends ConsumerState<_DesktopMusicMetadataDrawer> {
  static const int _maxLyricsBytes = 2 * 1024 * 1024;

  late final TextEditingController _title = TextEditingController(
    text: widget.track.title,
  );
  late final TextEditingController _artist = TextEditingController(
    text: widget.track.artistName,
  );
  late final TextEditingController _album = TextEditingController(
    text: widget.track.albumTitle,
  );
  late final TextEditingController _genre = TextEditingController(
    text: widget.track.genre ?? '',
  );
  // 仅回填外部手动封面 URL，绝不把内部 `/api/v1/music/covers/{fileId}` 填入外链框。
  late final TextEditingController _coverUrl = TextEditingController(
    text: _initialExternalCoverUrl(widget.track),
  );
  late final String _initialCoverUrl = _coverUrl.text;
  late final TextEditingController _lyrics = TextEditingController(
    text: widget.track.lyricsRaw ?? '',
  );
  late final TextEditingController _lyricsTranslation = TextEditingController(
    text: widget.track.lyricsTranslation ?? '',
  );
  DesktopPickedCover? _pickedCover;
  bool _clearCover = false;
  bool _loadingLyrics = false;
  bool _lyricsChanged = false;
  bool _translationChanged = false;
  bool _lyricsFocused = false;
  bool _translationFocused = false;
  bool _saving = false;
  String? _coverUrlError;

  static String _initialExternalCoverUrl(MusicTrack track) {
    final manual = track.manualCoverUrl?.trim();
    if (manual != null && manual.isNotEmpty && _isHttpUrl(manual)) {
      return manual;
    }
    return '';
  }

  static bool _isHttpUrl(String value) {
    if (value.length > 2048) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme.toLowerCase() == 'http' ||
            uri.scheme.toLowerCase() == 'https') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  @override
  void initState() {
    super.initState();
    if (widget.track.lyricsRaw == null ||
        widget.track.lyricsTranslation == null) {
      _loadingLyrics = true;
      unawaited(_loadLyrics());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    _genre.dispose();
    _coverUrl.dispose();
    _lyrics.dispose();
    _lyricsTranslation.dispose();
    super.dispose();
  }

  Future<void> _loadLyrics() async {
    try {
      final detail = await ref
          .read(musicCenterControllerProvider.notifier)
          .ensureTrackDetail(widget.track.id);
      if (!mounted) return;
      final state = ref.read(musicCenterControllerProvider).asData?.value;
      final latest =
          detail ??
          state?.tracks
              .where((track) => track.id == widget.track.id)
              .firstOrNull ??
          state?.playbackItems
              .where((item) => item.track.id == widget.track.id)
              .map((item) => item.track)
              .firstOrNull ??
          (state?.currentItem?.track.id == widget.track.id
              ? state?.currentItem?.track
              : null);
      if (!_lyricsChanged && latest?.lyricsRaw != null) {
        _lyrics.text = latest!.lyricsRaw!;
      }
      if (!_translationChanged && latest?.lyricsTranslation != null) {
        _lyricsTranslation.text = latest!.lyricsTranslation!;
      }
    } on Object catch (error) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        showDesktopToast(
          context,
          failureToast(l10n, l10n.musicNowPlayingLyrics, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _loadingLyrics = false);
    }
  }

  Future<void> _importLyricsFile({required bool isTranslation}) async {
    final l10n = AppLocalizations.of(context);
    try {
      final files = await FilePick.pickFiles(
        allowedExtensions: const ['lrc', 'txt', 'srt', 'vtt'],
      );
      if (!mounted || files.isEmpty) {
        return;
      }
      final bytes = await files.first.readBytes();
      if (!mounted || bytes.isEmpty) {
        return;
      }
      if (bytes.length > _maxLyricsBytes) {
        showDesktopToast(
          context,
          l10n.musicLyricsTooLarge,
          kind: DesktopToastKind.warn,
          icon: DesktopIcons.info,
        );
        return;
      }
      final decoded = utf8.decode(bytes, allowMalformed: true);
      setState(() {
        if (isTranslation) {
          _lyricsTranslation.text = decoded;
          _translationChanged = true;
        } else {
          _lyrics.text = decoded;
          _lyricsChanged = true;
        }
      });
    } on Object catch (_) {
      if (mounted) {
        showDesktopToast(
          context,
          l10n.musicLyricsReadFailed,
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final coverUrl = _coverUrl.text.trim();
    final coverUrlChanged = coverUrl != _initialCoverUrl.trim();
    if (_pickedCover == null &&
        !_clearCover &&
        coverUrlChanged &&
        coverUrl.isNotEmpty &&
        !_isHttpUrl(coverUrl)) {
      setState(() => _coverUrlError = l10n.musicCoverUrlInvalid);
      return;
    }
    setState(() => _coverUrlError = null);
    if (_title.text.trim().isEmpty) {
      showDesktopToast(
        context,
        l10n.musicTitleRequired,
        kind: DesktopToastKind.warn,
        icon: DesktopIcons.info,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final controller = ref.read(musicCenterControllerProvider.notifier);
      // 合并曲目信息、封面、原文歌词与译文歌词为单次原子保存。
      await controller.updateTrackMetadata(
        trackId: widget.track.id,
        title: _title.text.trim(),
        artistName: _artist.text.trim(),
        albumTitle: _album.text.trim(),
        genre: _genre.text.trim(),
        lyricsRaw: _lyricsChanged ? _lyrics.text : null,
        lyricsTranslation: _translationChanged ? _lyricsTranslation.text : null,
        coverBytes: _pickedCover?.bytes,
        coverFileName: _pickedCover?.fileName,
        coverUrl:
            !_clearCover && _pickedCover == null && coverUrlChanged
                ? coverUrl
                : null,
        clearCover: _clearCover && _pickedCover == null,
      );
      if (!mounted) return;
      showDesktopToast(
        context,
        l10n.musicMetadataSaved,
        kind: DesktopToastKind.success,
        icon: DesktopIcons.check,
      );
      closeDesktopModal(context, true);
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.musicEditMetadata, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restoreOriginal() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(musicCenterControllerProvider.notifier)
          .restoreTrackMetadata(widget.track.id);
      if (!mounted) return;
      showDesktopToast(
        context,
        l10n.musicMetadataRestored,
        kind: DesktopToastKind.success,
        icon: DesktopIcons.check,
      );
      closeDesktopModal(context, true);
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.musicEditMetadata, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);

    return DesktopDrawerFrame(
      eyebrow: l10n.musicMetadataEyebrow,
      title: l10n.musicEditTrack,
      footer: Row(
        children: [
          if (widget.track.hasManualOverride)
            DesktopButton(
              label: l10n.musicRestoreOriginal,
              icon: DesktopIcons.undo,
              onPressed: _saving ? null : () => unawaited(_restoreOriginal()),
            ),
          const Spacer(),
          DesktopButton(
            label: l10n.musicCancel,
            onPressed: _saving ? null : () => closeDesktopModal(context),
          ),
          const SizedBox(width: 10),
          DesktopButton(
            label: l10n.musicSave,
            variant: DesktopButtonVariant.primary,
            busy: _saving,
            onPressed:
                _saving || _title.text.trim().isEmpty
                    ? null
                    : () => unawaited(_save()),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopCoverField(
            label: l10n.musicCoverImageUrl,
            shape: DesktopCoverFieldShape.square,
            previewUrl: widget.track.coverUrl,
            coverKind: DesktopCoverKind.music,
            fallbackIcon: DesktopIcons.music,
            urlController: _coverUrl,
            pickedCover: _pickedCover,
            cleared: _clearCover,
            urlError: _coverUrlError,
            enabled: !_saving,
            onPicked: (picked) {
              setState(() {
                _pickedCover = picked;
                _clearCover = false;
                _coverUrlError = null;
              });
            },
            onClear: () {
              setState(() {
                _pickedCover = null;
                _clearCover = true;
                _coverUrlError = null;
              });
            },
            onUrlChanged: (_) {
              setState(() {
                _pickedCover = null;
                _clearCover = false;
                _coverUrlError = null;
              });
            },
          ),
          const SizedBox(height: 16),
          DesktopTextField(
            controller: _title,
            label: l10n.musicFieldTitle,
            required: true,
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DesktopTextField(
                  controller: _artist,
                  label: l10n.musicFieldArtist,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DesktopTextField(
                  controller: _genre,
                  label: l10n.musicFieldGenre,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DesktopTextField(controller: _album, label: l10n.musicFieldAlbum),
          const SizedBox(height: 16),
          _lyricsHeader(
            skin: skin,
            label: l10n.musicNowPlayingLyrics,
            lineCount: _lineCount,
            l10n: l10n,
            hasText: _lyrics.text.isNotEmpty,
            loading: _loadingLyrics,
            onImport: () => unawaited(_importLyricsFile(isTranslation: false)),
            onClear: () {
              setState(() {
                _lyrics.clear();
                _lyricsChanged = true;
              });
            },
          ),
          const SizedBox(height: 6),
          _multilineLyricsField(
            skin: skin,
            controller: _lyrics,
            focused: _lyricsFocused,
            minLines: 7,
            maxLines: 10,
            hintText: l10n.musicLyricsEditHint,
            onFocusChange: (focused) {
              if (mounted) setState(() => _lyricsFocused = focused);
            },
            onChanged: (_) => setState(() => _lyricsChanged = true),
          ),
          const SizedBox(height: 14),
          _lyricsHeader(
            skin: skin,
            label: l10n.musicVisualizerLyricTranslation,
            lineCount: _translationLineCount,
            l10n: l10n,
            hasText: _lyricsTranslation.text.isNotEmpty,
            loading: false,
            onImport: () => unawaited(_importLyricsFile(isTranslation: true)),
            onClear: () {
              setState(() {
                _lyricsTranslation.clear();
                _translationChanged = true;
              });
            },
          ),
          const SizedBox(height: 6),
          _multilineLyricsField(
            skin: skin,
            controller: _lyricsTranslation,
            focused: _translationFocused,
            minLines: 5,
            maxLines: 8,
            hintText: l10n.musicLyricsEditHint,
            onFocusChange: (focused) {
              if (mounted) setState(() => _translationFocused = focused);
            },
            onChanged: (_) => setState(() => _translationChanged = true),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.musicMetadataScopeNote,
            style: DesktopType.caption(skin.text3),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _lyricsHeader({
    required DesktopSkin skin,
    required String label,
    required int lineCount,
    required AppLocalizations l10n,
    required bool hasText,
    required bool loading,
    required VoidCallback onImport,
    required VoidCallback onClear,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              style: DesktopType.fieldLabel(skin.text2),
              children: [
                TextSpan(text: label),
                TextSpan(
                  text: ' · ${l10n.musicLyricsLineCount(lineCount)}',
                  style: DesktopType.fieldHint(skin.text3),
                ),
              ],
            ),
          ),
        ),
        if (loading) ...[
          const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
        ],
        DesktopButton(
          label: l10n.musicLyricsFile,
          icon: DesktopIcons.upload,
          variant: DesktopButtonVariant.ghost,
          tooltip: l10n.musicLyricsPick,
          onPressed: _saving ? null : onImport,
        ),
        if (hasText) ...[
          const SizedBox(width: 4),
          DesktopButton(
            label: l10n.musicLyricsClear,
            icon: DesktopIcons.close,
            variant: DesktopButtonVariant.ghost,
            onPressed: _saving ? null : onClear,
          ),
        ],
      ],
    );
  }

  Widget _multilineLyricsField({
    required DesktopSkin skin,
    required TextEditingController controller,
    required bool focused,
    required int minLines,
    required int maxLines,
    required String hintText,
    required ValueChanged<bool> onFocusChange,
    required ValueChanged<String> onChanged,
  }) {
    return Focus(
      onFocusChange: onFocusChange,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DesktopMetrics.radiusButton),
          boxShadow:
              focused
                  ? [
                    BoxShadow(
                      color: skin.accent.withValues(alpha: 0.18),
                      blurRadius: 0,
                      spreadRadius: 4,
                    ),
                  ]
                  : const [],
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          minLines: minLines,
          maxLines: maxLines,
          keyboardType: TextInputType.multiline,
          textAlignVertical: TextAlignVertical.top,
          style: DesktopType.field(skin.text),
          cursorColor: skin.accent,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: DesktopType.field(skin.text3),
            filled: true,
            fillColor: focused ? skin.raise2 : skin.raise,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesktopMetrics.radiusButton),
              borderSide: BorderSide(color: skin.line2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesktopMetrics.radiusButton),
              borderSide: BorderSide(color: skin.line2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesktopMetrics.radiusButton),
              borderSide: BorderSide(color: skin.accent),
            ),
          ),
        ),
      ),
    );
  }

  int get _lineCount =>
      _lyrics.text
          .split(RegExp(r'\r?\n'))
          .where((line) => line.trim().isNotEmpty)
          .length;

  int get _translationLineCount =>
      _lyricsTranslation.text
          .split(RegExp(r'\r?\n'))
          .where((line) => line.trim().isNotEmpty)
          .length;
}
