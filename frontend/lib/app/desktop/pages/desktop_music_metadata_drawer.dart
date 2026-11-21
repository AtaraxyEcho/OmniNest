import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/music/music_portal.dart';

Future<bool?> showDesktopMusicMetadataDrawer({
  required BuildContext context,
  required MusicTrack track,
}) {
  return showDesktopDrawer<bool>(
    context,
    width: 480,
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
  late final TextEditingController _title = TextEditingController(
    text: widget.track.title,
  );
  late final TextEditingController _artist = TextEditingController(
    text: widget.track.artistName,
  );
  late final TextEditingController _album = TextEditingController(
    text: widget.track.albumTitle,
  );
  late final TextEditingController _coverUrl = TextEditingController(
    text: widget.track.manualCoverUrl ?? widget.track.coverUrl ?? '',
  );
  late final String _initialCoverUrl = _coverUrl.text;
  late final TextEditingController _lyrics = TextEditingController(
    text: widget.track.lyricsRaw ?? '',
  );
  late final TextEditingController _lyricsTranslation = TextEditingController(
    text: widget.track.lyricsTranslation ?? '',
  );
  bool _loadingLyrics = false;
  bool _lyricsChanged = false;
  bool _translationChanged = false;
  bool _lyricsFocused = false;
  bool _translationFocused = false;
  bool _saving = false;
  String? _coverUrlError;

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
    _coverUrl.dispose();
    _lyrics.dispose();
    _lyricsTranslation.dispose();
    super.dispose();
  }

  Future<void> _loadLyrics() async {
    try {
      await ref
          .read(musicCenterControllerProvider.notifier)
          .ensureTrackDetail(widget.track.id);
      if (!mounted) return;
      final latest =
          ref
              .read(musicCenterControllerProvider)
              .asData
              ?.value
              .tracks
              .where((track) => track.id == widget.track.id)
              .firstOrNull;
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

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final coverUrl = _coverUrl.text.trim();
    final coverUrlChanged = coverUrl != _initialCoverUrl.trim();
    if (coverUrlChanged && coverUrl.isNotEmpty && !_isHttpUrl(coverUrl)) {
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
      await controller.updateTrackMetadata(
        trackId: widget.track.id,
        title: _title.text.trim(),
        artistName: _artist.text.trim(),
        albumTitle: _album.text.trim(),
        lyricsRaw: _lyricsChanged ? _lyrics.text : null,
        coverUrl: coverUrlChanged ? coverUrl : null,
      );
      if (_translationChanged) {
        await controller.applyLyrics(
          widget.track,
          _lyrics.text,
          lyricsTranslation: _lyricsTranslation.text,
        );
      }
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

  bool _isHttpUrl(String value) {
    if (value.length > 2048) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme.toLowerCase() == 'http' ||
            uri.scheme.toLowerCase() == 'https') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
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
      closeDesktopModal(context, false);
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
    final isZh = Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('zh');

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 22),
                child: SizedBox.square(
                  dimension: 96,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                          spreadRadius: -10,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: DesktopCover(
                        url:
                            _coverUrl.text.trim().isEmpty
                                ? widget.track.coverUrl
                                : _coverUrl.text.trim(),
                        fallbackIcon: DesktopIcons.music,
                        cacheKey:
                            'music-metadata-cover:${widget.track.id}:${_coverUrl.text.trim()}',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DesktopTextField(
                      controller: _title,
                      label: l10n.musicFieldTitle,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),
                    DesktopTextField(
                      controller: _artist,
                      label: l10n.musicFieldArtist,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          DesktopTextField(controller: _album, label: l10n.musicFieldAlbum),
          const SizedBox(height: 14),
          DesktopTextField(
            controller: _coverUrl,
            label: l10n.musicCoverImageUrl,
            hint: 'https://',
            keyboardType: TextInputType.url,
            error: _coverUrlError,
            onChanged: (_) => setState(() => _coverUrlError = null),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: DesktopType.fieldLabel(skin.text2),
                    children: [
                      TextSpan(text: l10n.musicNowPlayingLyrics),
                      TextSpan(
                        text: ' · ${l10n.musicLyricsLineCount(_lineCount)}',
                        style: DesktopType.fieldHint(skin.text3),
                      ),
                    ],
                  ),
                ),
              ),
              if (_loadingLyrics)
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _multilineLyricsField(
            skin: skin,
            controller: _lyrics,
            focused: _lyricsFocused,
            minLines: 8,
            maxLines: 10,
            hintText: l10n.musicLyricsEditHint,
            onFocusChange: (focused) {
              if (mounted) setState(() => _lyricsFocused = focused);
            },
            onChanged: (_) => setState(() => _lyricsChanged = true),
          ),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(
              style: DesktopType.fieldLabel(skin.text2),
              children: [
                TextSpan(text: isZh ? '译文歌词（LRC）' : 'Translated lyrics (LRC)'),
                TextSpan(
                  text:
                      ' · ${l10n.musicLyricsLineCount(_translationLineCount)}',
                  style: DesktopType.fieldHint(skin.text3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _multilineLyricsField(
            skin: skin,
            controller: _lyricsTranslation,
            focused: _translationFocused,
            minLines: 6,
            maxLines: 8,
            hintText:
                isZh
                    ? '可选：粘贴与原文时间戳对齐的译文 LRC（如 [00:12.34]译文内容）'
                    : 'Optional: paste timestamp-aligned translated LRC lines',
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
