import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/app/theme/feature/music_backdrop_theme.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';

/// 音乐曲目元数据编辑页。
///
/// 视觉取向为极简编辑器：封面主视觉 + 发丝分割线 + 下划线表单，
/// 不使用厚重卡片堆叠，操作集中在底部动作条。
class MusicMetadataEditPage extends ConsumerWidget {
  const MusicMetadataEditPage({required this.trackId, super.key});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(musicCenterControllerProvider);
    final track =
        state.asData?.value.tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) {
      return const Scaffold(body: AppLoading.detail());
    }
    return Theme(
      data: MusicBackdropTheme.withNeutralTextButtons(Theme.of(context)),
      child: Scaffold(
        backgroundColor: context.musicColors.background,
        body: _MetadataEditForm(track: track),
      ),
    );
  }
}

class _MetadataEditForm extends ConsumerStatefulWidget {
  const _MetadataEditForm({required this.track});

  final MusicTrack track;

  @override
  ConsumerState<_MetadataEditForm> createState() => _MetadataEditFormState();
}

class _MetadataEditFormState extends ConsumerState<_MetadataEditForm> {
  int _filePickGeneration = 0;
  int _scrapeGeneration = 0;
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;
  late final TextEditingController _genreController;
  bool _saving = false;
  bool _scrapeLoading = false;
  bool _lyricsSearching = false;
  List<MusicScrapeCandidate>? _scrapeCandidates;
  String? _coverFileName;
  List<int>? _coverBytes;
  bool _clearCover = false;
  String? _lyricsFileName;
  String? _lyricsContent;

  /// 列表投影不带歌词：打开编辑页时补拉完整曲目，完成后关闭加载态。
  bool _lyricsDetailPending = false;

  @override
  void initState() {
    super.initState();
    final track = widget.track;
    _titleController = TextEditingController(text: track.title);
    _artistController = TextEditingController(text: track.artistName);
    _albumController = TextEditingController(text: track.albumTitle);
    _genreController = TextEditingController(text: track.genre ?? '');
    if (track.lyricsRaw?.isNotEmpty != true) {
      _lyricsDetailPending = true;
      unawaited(_loadTrackDetail());
    }
  }

  Future<void> _loadTrackDetail() async {
    try {
      await ref
          .read(musicCenterControllerProvider.notifier)
          .ensureTrackDetail(widget.track.id);
    } finally {
      if (mounted) {
        setState(() => _lyricsDetailPending = false);
      }
    }
  }

  @override
  void dispose() {
    _filePickGeneration++;
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _genreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    return SafeArea(
      child: Column(
        children: [
          _EditHeader(
            onBack: () => Navigator.of(context).pop(),
            onMatchOnline: _scrapeLoading ? null : _matchOnline,
            scrapeLoading: _scrapeLoading,
          ),
          _HairlineDivider(color: colors.outline),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 880;
                final content = _EditorBody(
                  track: widget.track,
                  wide: wide,
                  titleController: _titleController,
                  artistController: _artistController,
                  albumController: _albumController,
                  genreController: _genreController,
                  coverBytes: _coverBytes,
                  coverFileName: _coverFileName,
                  clearCover: _clearCover,
                  lyricsFileName: _lyricsFileName,
                  existingLyrics: widget.track.lyricsRaw,
                  pendingLyrics: _lyricsContent,
                  lyricsDetailPending: _lyricsDetailPending,
                  onPickCover: _pickCover,
                  onRemoveCover: _removeCover,
                  onPickLyrics: _pickLyrics,
                  onClearLyrics: _clearLyrics,
                  onSearchLyrics: _lyricsSearching ? null : _searchLyrics,
                  searchingLyrics: _lyricsSearching,
                  scrapeCandidates: _scrapeCandidates,
                  scrapeLoading: _scrapeLoading,
                  onApplyCandidate: _applyCandidate,
                );
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1040),
                      child: content,
                    ),
                  ),
                );
              },
            ),
          ),
          _HairlineDivider(color: colors.outline),
          _EditActionBar(
            saving: _saving,
            onCancel: _saving ? null : () => Navigator.of(context).pop(),
            onSave: _saving ? null : _save,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showMessage(AppLocalizations.of(context).musicTitleRequired);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(musicCenterControllerProvider.notifier)
          .updateTrackMetadata(
            trackId: widget.track.id,
            title: title,
            artistName: _blankToNull(_artistController.text),
            albumTitle: _blankToNull(_albumController.text),
            genre: _genreController.text.trim(),
            lyricsRaw: _lyricsContent,
            coverBytes: _coverBytes,
            coverFileName: _coverFileName,
            clearCover: _clearCover,
          );
      if (mounted) {
        _showMessage(AppLocalizations.of(context).musicMetadataSaved);
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          AppLocalizations.of(
            context,
          ).musicSaveFailed(describeUserFacingError(error).message),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _searchLyrics() async {
    setState(() => _lyricsSearching = true);
    MusicLyricsResult? result;
    Object? failure;
    try {
      result = await ref
          .read(musicCenterControllerProvider.notifier)
          .searchLyrics(widget.track);
    } on Object catch (error) {
      failure = error;
    }
    if (!mounted) {
      return;
    }
    setState(() => _lyricsSearching = false);
    if (failure != null) {
      _showMessage(
        AppLocalizations.of(context).musicSaveFailed(failure.toString()),
      );
      return;
    }
    final lyrics = result?.bestLyrics;
    if (lyrics == null) {
      _showMessage(AppLocalizations.of(context).musicLyricsNoResult);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        final candidate = result!;
        final preview = candidate.bestLyrics ?? '';
        return AlertDialog(
          title: Text(l10n.musicLyricsSearch),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${candidate.trackName ?? widget.track.title} — ${candidate.artistName ?? widget.track.artistName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(dialogContext).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: SingleChildScrollView(
                    child: Text(
                      preview,
                      style: Theme.of(dialogContext).textTheme.bodySmall
                          ?.copyWith(fontFamily: AppTypography.monoFamily),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.musicCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.musicLyricsApply),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _lyricsSearching = true);
    try {
      final updated = await ref
          .read(musicCenterControllerProvider.notifier)
          .applyLyrics(widget.track, lyrics);
      if (!mounted) {
        return;
      }
      setState(() {
        _lyricsContent = lyrics;
        _lyricsFileName = AppLocalizations.of(context).musicLyricsOnlineSource;
      });
      _showMessage(
        AppLocalizations.of(context).musicLyricsApplied(updated.title),
      );
    } on Object catch (error) {
      if (mounted) {
        _showMessage(
          AppLocalizations.of(
            context,
          ).musicSaveFailed(describeUserFacingError(error).message),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _lyricsSearching = false);
      }
    }
  }

  Future<void> _matchOnline() async {
    final generation = ++_scrapeGeneration;
    setState(() {
      _scrapeLoading = true;
      _scrapeCandidates = null;
    });
    try {
      final candidates = await ref
          .read(musicCenterControllerProvider.notifier)
          .scrapeCandidates(widget.track);
      if (!mounted || generation != _scrapeGeneration) {
        return;
      }
      setState(() => _scrapeCandidates = candidates);
    } on Object catch (error) {
      if (!mounted || generation != _scrapeGeneration) {
        return;
      }
      setState(() => _scrapeCandidates = const <MusicScrapeCandidate>[]);
      _showMessage(
        AppLocalizations.of(
          context,
        ).musicSaveFailed(describeUserFacingError(error).message),
      );
    } finally {
      if (mounted && generation == _scrapeGeneration) {
        setState(() => _scrapeLoading = false);
      }
    }
  }

  Future<void> _applyCandidate(MusicScrapeCandidate candidate) async {
    final generation = ++_scrapeGeneration;
    setState(() => _scrapeLoading = true);
    try {
      await ref
          .read(musicCenterControllerProvider.notifier)
          .applyScrapeCandidate(widget.track, candidate);
      if (!mounted) {
        return;
      }
      final updated =
          ref
              .read(musicCenterControllerProvider)
              .asData
              ?.value
              .tracks
              .where((t) => t.id == widget.track.id)
              .firstOrNull;
      if (updated != null) {
        _titleController.text = updated.title;
        _artistController.text = updated.artistName;
        _albumController.text = updated.albumTitle;
        _genreController.text = updated.genre ?? '';
      }
      _showMessage(AppLocalizations.of(context).musicScrapeApplied);
    } on Object catch (error) {
      if (mounted) {
        _showMessage(
          AppLocalizations.of(
            context,
          ).musicSaveFailed(describeUserFacingError(error).message),
        );
      }
    } finally {
      if (mounted && generation == _scrapeGeneration) {
        setState(() => _scrapeLoading = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String? _blankToNull(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _pickCover() async {
    final generation = ++_filePickGeneration;
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (!mounted || generation != _filePickGeneration) {
      return;
    }
    if (result.isNotEmpty) {
      final file = result.first;
      final bytes = await file.readAsBytes();
      if (!mounted || generation != _filePickGeneration) {
        return;
      }
      setState(() {
        _coverFileName = file.name;
        _coverBytes = bytes;
        _clearCover = false;
      });
    }
  }

  /// 清除本地待传封面；否则标记保存时显式清空服务端封面。
  void _removeCover() {
    setState(() {
      if (_coverBytes != null) {
        _coverBytes = null;
        _coverFileName = null;
        return;
      }
      _clearCover = true;
    });
  }

  /// 清空歌词：以空字符串提交，后端会同时清空原文与译文。
  void _clearLyrics() {
    setState(() {
      _lyricsContent = '';
      _lyricsFileName = null;
    });
  }

  Future<void> _pickLyrics() async {
    final generation = ++_filePickGeneration;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['lrc', 'txt', 'srt', 'vtt'],
    );
    if (!mounted || generation != _filePickGeneration) {
      return;
    }
    if (result.isNotEmpty) {
      final file = result.first;
      final bytes = await file.readAsBytes();
      if (!mounted || generation != _filePickGeneration) {
        return;
      }
      String? content;
      if (bytes.isNotEmpty) {
        content = utf8.decode(bytes);
      } else if (file.path != null && !kIsWeb) {
        content = await File(file.path!).readAsString();
        if (!mounted || generation != _filePickGeneration) {
          return;
        }
      }
      setState(() {
        _lyricsFileName = file.name;
        _lyricsContent = content;
      });
    }
  }
}

class _EditHeader extends StatelessWidget {
  const _EditHeader({
    required this.onBack,
    required this.onMatchOnline,
    required this.scrapeLoading,
  });

  final VoidCallback onBack;
  final VoidCallback? onMatchOnline;
  final bool scrapeLoading;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 20, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: l10n.musicCancel,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 4),
          Text(
            l10n.musicEditMetadata,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onMatchOnline,
            icon:
                scrapeLoading
                    ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.travel_explore_rounded, size: 18),
            label: Text(l10n.musicScrapeMatch),
            style: TextButton.styleFrom(
              foregroundColor: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditActionBar extends StatelessWidget {
  const _EditActionBar({
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final bool saving;
  final VoidCallback? onCancel;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: onCancel,
            style: OutlinedButton.styleFrom(
              minimumSize: Size(88, AppControlTokens.buttonHeight),
              padding: AppControlTokens.buttonPadding,
            ),
            child: Text(l10n.musicCancel),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: onSave,
            style: FilledButton.styleFrom(
              minimumSize: Size(96, AppControlTokens.buttonHeight),
              padding: AppControlTokens.buttonPadding,
            ),
            child:
                saving
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : Text(l10n.musicSave),
          ),
        ],
      ),
    );
  }
}

class _EditorBody extends StatelessWidget {
  const _EditorBody({
    required this.track,
    required this.wide,
    required this.titleController,
    required this.artistController,
    required this.albumController,
    required this.genreController,
    required this.coverBytes,
    required this.coverFileName,
    required this.clearCover,
    required this.lyricsFileName,
    required this.existingLyrics,
    required this.pendingLyrics,
    required this.lyricsDetailPending,
    required this.onPickCover,
    required this.onRemoveCover,
    required this.onPickLyrics,
    required this.onClearLyrics,
    required this.onSearchLyrics,
    required this.searchingLyrics,
    required this.scrapeCandidates,
    required this.scrapeLoading,
    required this.onApplyCandidate,
  });

  final MusicTrack track;
  final bool wide;
  final TextEditingController titleController;
  final TextEditingController artistController;
  final TextEditingController albumController;
  final TextEditingController genreController;
  final List<int>? coverBytes;
  final String? coverFileName;
  final bool clearCover;
  final String? lyricsFileName;
  final String? existingLyrics;
  final String? pendingLyrics;
  final bool lyricsDetailPending;
  final VoidCallback onPickCover;
  final VoidCallback onRemoveCover;
  final VoidCallback onPickLyrics;
  final VoidCallback onClearLyrics;
  final VoidCallback? onSearchLyrics;
  final bool searchingLyrics;
  final List<MusicScrapeCandidate>? scrapeCandidates;
  final bool scrapeLoading;
  final ValueChanged<MusicScrapeCandidate> onApplyCandidate;

  @override
  Widget build(BuildContext context) {
    final coverPanel = _CoverPanel(
      track: track,
      previewBytes: coverBytes,
      pendingFileName: coverFileName,
      clearCover: clearCover,
      onPickCover: onPickCover,
      onRemoveCover: onRemoveCover,
    );
    final formPanel = _FormFields(
      titleController: titleController,
      artistController: artistController,
      albumController: albumController,
      genreController: genreController,
    );
    final lyricsSection = _LyricsSection(
      lyricsFileName: lyricsFileName,
      existingLyrics: existingLyrics,
      pendingLyrics: pendingLyrics,
      detailPending: lyricsDetailPending,
      onPickLyrics: onPickLyrics,
      onClearLyrics: onClearLyrics,
      onSearchLyrics: onSearchLyrics,
      searchingLyrics: searchingLyrics,
    );

    final candidatesSection =
        scrapeCandidates == null
            ? null
            : _ScrapeCandidates(
              candidates: scrapeCandidates!,
              applying: scrapeLoading,
              onApply: onApplyCandidate,
            );

    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: coverPanel),
          const SizedBox(height: 28),
          formPanel,
          const SizedBox(height: 28),
          lyricsSection,
          if (candidatesSection != null) ...[
            const SizedBox(height: 28),
            candidatesSection,
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 260, child: coverPanel),
            const SizedBox(width: 40),
            Expanded(child: formPanel),
          ],
        ),
        const SizedBox(height: 32),
        lyricsSection,
        if (candidatesSection != null) ...[
          const SizedBox(height: 28),
          candidatesSection,
        ],
      ],
    );
  }
}

class _CoverPanel extends StatefulWidget {
  const _CoverPanel({
    required this.track,
    required this.previewBytes,
    required this.pendingFileName,
    required this.clearCover,
    required this.onPickCover,
    required this.onRemoveCover,
  });

  final MusicTrack track;
  final List<int>? previewBytes;
  final String? pendingFileName;
  final bool clearCover;
  final VoidCallback onPickCover;
  final VoidCallback onRemoveCover;

  @override
  State<_CoverPanel> createState() => _CoverPanelState();
}

class _CoverPanelState extends State<_CoverPanel> {
  bool _hovering = false;

  bool get _hasPendingSelection => widget.previewBytes != null;

  bool get _hasCoverToClear =>
      _hasPendingSelection ||
      (!widget.clearCover && widget.track.coverUrl?.isNotEmpty == true);

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final showRemoteCover = widget.previewBytes == null && !widget.clearCover;
    return Column(
      children: [
        Semantics(
          button: true,
          label: l10n.musicCoverPick,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: InkWell(
              onTap: widget.onPickCover,
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: 0.18),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox.square(
                        dimension: 220,
                        child:
                            widget.previewBytes != null
                                ? Image.memory(
                                  Uint8List.fromList(widget.previewBytes!),
                                  fit: BoxFit.cover,
                                )
                                : MusicDeckArtwork(
                                  title: widget.track.title,
                                  imageUrl:
                                      showRemoteCover
                                          ? widget.track.coverUrl
                                          : null,
                                  borderRadius: 12,
                                  icon: Icons.album_rounded,
                                ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _hovering ? 1 : 0,
                        duration: const Duration(milliseconds: 160),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: colors.overlay.withValues(alpha: 0.36),
                          ),
                          child: Icon(
                            Icons.photo_camera_outlined,
                            color: scheme.onPrimary.withValues(alpha: 0.92),
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          widget.pendingFileName ??
              (widget.clearCover ? l10n.musicCoverRemove : l10n.musicCoverPick),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (_hasCoverToClear) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: widget.onRemoveCover,
            child: Text(
              _hasPendingSelection ? l10n.musicCancel : l10n.musicCoverRemove,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          widget.track.qualityText,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

class _FormFields extends StatelessWidget {
  const _FormFields({
    required this.titleController,
    required this.artistController,
    required this.albumController,
    required this.genreController,
  });

  final TextEditingController titleController;
  final TextEditingController artistController;
  final TextEditingController albumController;
  final TextEditingController genreController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _UnderlineField(
          label: l10n.musicFieldTitle,
          controller: titleController,
          required: true,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 22),
        _UnderlineField(
          label: l10n.musicFieldArtist,
          controller: artistController,
        ),
        const SizedBox(height: 22),
        _UnderlineField(
          label: l10n.musicFieldAlbum,
          controller: albumController,
        ),
        const SizedBox(height: 22),
        _UnderlineField(
          label: l10n.musicFieldGenre,
          controller: genreController,
        ),
      ],
    );
  }
}

class _UnderlineField extends StatelessWidget {
  const _UnderlineField({
    required this.label,
    required this.controller,
    this.required = false,
    this.style,
  });

  final String label;
  final TextEditingController controller;
  final bool required;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          required ? '$label *' : label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          style:
              style ??
              Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colors.onSurface,
                height: 1.4,
              ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.only(bottom: 10, top: 4),
            border: _underline(colors.outline),
            enabledBorder: _underline(colors.outline),
            focusedBorder: _underline(colors.primary, width: 1.5),
            errorBorder: _underline(colors.danger),
            focusedErrorBorder: _underline(colors.danger, width: 1.5),
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _underline(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

class _LyricsSection extends StatelessWidget {
  const _LyricsSection({
    required this.lyricsFileName,
    required this.existingLyrics,
    required this.pendingLyrics,
    required this.detailPending,
    required this.onPickLyrics,
    required this.onClearLyrics,
    required this.onSearchLyrics,
    required this.searchingLyrics,
  });

  final String? lyricsFileName;
  final String? existingLyrics;
  final String? pendingLyrics;
  final bool detailPending;
  final VoidCallback onPickLyrics;
  final VoidCallback onClearLyrics;
  final VoidCallback? onSearchLyrics;
  final bool searchingLyrics;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final l10n = AppLocalizations.of(context);
    final previewSource = pendingLyrics ?? existingLyrics;
    final preview = previewSource?.trim() ?? '';
    final cleared = pendingLyrics == '';
    final status =
        cleared
            ? l10n.musicNoLyrics
            : pendingLyrics != null
            ? l10n.musicLyricsOnlineSource
            : preview.isNotEmpty
            ? l10n.musicLyricsExisting
            : l10n.musicNoLyrics;
    final canClear = !cleared && preview.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.musicLyricsFile,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: onPickLyrics,
              icon: const Icon(Icons.lyrics_rounded, size: 18),
              label: Text(lyricsFileName ?? l10n.musicLyricsPick),
              style: OutlinedButton.styleFrom(
                minimumSize: Size(0, AppControlTokens.buttonHeight),
                padding: AppControlTokens.buttonPadding,
              ),
            ),
            OutlinedButton.icon(
              onPressed: onSearchLyrics,
              icon:
                  searchingLyrics
                      ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.travel_explore_rounded, size: 18),
              label: Text(l10n.musicLyricsSearch),
              style: OutlinedButton.styleFrom(
                minimumSize: Size(0, AppControlTokens.buttonHeight),
                padding: AppControlTokens.buttonPadding,
              ),
            ),
            if (canClear)
              TextButton(
                onPressed: onClearLyrics,
                child: Text(l10n.musicLyricsClear),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (detailPending && preview.isEmpty)
          const Align(
            alignment: Alignment.centerLeft,
            child: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else ...[
          Text(
            status,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: colors.fieldFill.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.fieldBorder),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    preview,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: AppTypography.monoFamily,
                      height: 1.55,
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _ScrapeCandidates extends StatelessWidget {
  const _ScrapeCandidates({
    required this.candidates,
    required this.applying,
    required this.onApply,
  });

  final List<MusicScrapeCandidate> candidates;
  final bool applying;
  final ValueChanged<MusicScrapeCandidate> onApply;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.musicScrapeCandidatesTitle,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
        const SizedBox(height: 12),
        if (candidates.isEmpty)
          Text(
            l10n.musicScrapeNoCandidates,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          )
        else
          for (final candidate in candidates)
            _ScrapeCandidateRow(
              candidate: candidate,
              applying: applying,
              onApply: () => onApply(candidate),
            ),
      ],
    );
  }
}

class _ScrapeCandidateRow extends StatelessWidget {
  const _ScrapeCandidateRow({
    required this.candidate,
    required this.applying,
    required this.onApply,
  });

  final MusicScrapeCandidate candidate;
  final bool applying;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final l10n = AppLocalizations.of(context);
    final chips = <String>[
      if (candidate.releaseDate != null)
        '${candidate.releaseDate!.year}-${candidate.releaseDate!.month.toString().padLeft(2, '0')}-${candidate.releaseDate!.day.toString().padLeft(2, '0')}',
      if (candidate.durationSeconds != null)
        _formatDuration(candidate.durationSeconds!),
      if (candidate.trackNumber != null) '#${candidate.trackNumber}',
      if (candidate.coverUrl != null) l10n.musicCoverImage,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: applying ? null : onApply,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        candidate.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${candidate.artistName} · ${candidate.albumTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final chip in chips)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.fieldFill,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: colors.fieldBorder),
                                ),
                                child: Text(
                                  chip,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelSmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: applying ? null : onApply,
                  style: FilledButton.styleFrom(
                    minimumSize: Size(0, AppControlTokens.buttonHeight),
                    padding: AppControlTokens.buttonPadding,
                  ),
                  child: Text(l10n.musicScrapeApply),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
  }
}

class _HairlineDivider extends StatelessWidget {
  const _HairlineDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: color.withValues(alpha: 0.55));
  }
}
