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
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/core/log/dev_log.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';

part 'music_metadata_edit_sections.dart';

/// 打开音乐曲目元数据编辑弹窗。
///
/// 返回 true 表示已保存提交；中途取消或关闭返回 null/false。
Future<bool?> showMusicMetadataEditDialog({
  required BuildContext context,
  required String trackId,
}) {
  return showWorkstationDialog<bool>(
    context: context,
    builder: (dialogContext) => MusicMetadataEditDialog(trackId: trackId),
  );
}

/// 音乐曲目元数据编辑弹窗。
///
/// 视觉取向为极简编辑器：封面主视觉 + 发丝分割线 + 下划线表单，
/// 不使用厚重卡片堆叠，操作集中在底部动作条；反馈一律内联呈现，
/// 不再经 ScaffoldMessenger 弹 SnackBar。
class MusicMetadataEditDialog extends ConsumerWidget {
  const MusicMetadataEditDialog({required this.trackId, super.key});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(musicCenterControllerProvider);
    final track =
        state.asData?.value.tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) {
      return const _MetadataEditLoadingDialog();
    }
    return Theme(
      data: MusicBackdropTheme.withNeutralTextButtons(Theme.of(context)),
      child: _MetadataEditForm(track: track),
    );
  }
}

/// 曲目尚未在列表状态中就位时的占位弹窗壳。
class _MetadataEditLoadingDialog extends StatelessWidget {
  const _MetadataEditLoadingDialog();

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    return AlertDialog(
      backgroundColor: colors.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outline),
      ),
      content: const SizedBox(
        width: 640,
        height: 220,
        child: Center(child: AppLoading.detail()),
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

  /// 列表投影不带歌词：打开编辑弹窗时补拉完整曲目，完成后关闭加载态。
  bool _lyricsDetailPending = false;

  /// 弹窗内联反馈：空为无反馈；[_statusIsError] 区分错误与成功文案。
  String? _statusMessage;
  bool _statusIsError = false;

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
    } on Object catch (error) {
      // Exception 已由中心控制器消化为 errorMessage；此处仅兜住 Error 类，
      // 避免 unawaited 调用把异常抛进全局 Zone。
      if (kDebugMode) {
        devLog('曲目详情补拉异常: trackId=${widget.track.id}, error=$error');
      }
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

  void _setStatus(String message, {bool error = false}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _statusMessage = message;
      _statusIsError = error;
    });
  }

  void _clearStatus() {
    if (_statusMessage == null) {
      return;
    }
    setState(() => _statusMessage = null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final l10n = AppLocalizations.of(context);
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
          Icon(Icons.edit_note_rounded, color: colors.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.musicEditMetadata,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: AppTypography.titleLarge,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _scrapeLoading ? null : _matchOnline,
            icon:
                _scrapeLoading
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
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
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
        width: 640,
        child: _EditorBody(
          track: widget.track,
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
          statusMessage: _statusMessage,
          statusIsError: _statusIsError,
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 22),
      actions: [
        OutlinedButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            minimumSize: Size(88, AppControlTokens.buttonHeight),
            padding: AppControlTokens.buttonPadding,
          ),
          child: Text(l10n.musicCancel),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            minimumSize: Size(96, AppControlTokens.buttonHeight),
            padding: AppControlTokens.buttonPadding,
          ),
          child:
              _saving
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : Text(l10n.musicSave),
        ),
      ],
    );
  }

  Future<void> _save() async {
    _clearStatus();
    final l10n = AppLocalizations.of(context);
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _setStatus(l10n.musicTitleRequired, error: true);
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
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        _setStatus(
          l10n.musicSaveFailed(describeUserFacingError(error).message),
          error: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _searchLyrics() async {
    _clearStatus();
    final l10n = AppLocalizations.of(context);
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
      _setStatus(l10n.musicSaveFailed(failure.toString()), error: true);
      return;
    }
    final lyrics = result?.bestLyrics;
    if (lyrics == null) {
      _setStatus(l10n.musicLyricsNoResult);
      return;
    }
    final confirmed = await showWorkstationDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        final candidate = result!;
        final preview = candidate.bestLyrics ?? '';
        final colors = dialogContext.musicColors;
        return AlertDialog(
          backgroundColor: colors.surfaceContainer,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: colors.outline),
          ),
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
        _lyricsFileName = l10n.musicLyricsOnlineSource;
      });
      _setStatus(l10n.musicLyricsApplied(updated.title));
    } on Object catch (error) {
      if (mounted) {
        _setStatus(
          l10n.musicSaveFailed(describeUserFacingError(error).message),
          error: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _lyricsSearching = false);
      }
    }
  }

  Future<void> _matchOnline() async {
    _clearStatus();
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
      _setStatus(
        AppLocalizations.of(
          context,
        ).musicSaveFailed(describeUserFacingError(error).message),
        error: true,
      );
    } finally {
      if (mounted && generation == _scrapeGeneration) {
        setState(() => _scrapeLoading = false);
      }
    }
  }

  Future<void> _applyCandidate(MusicScrapeCandidate candidate) async {
    _clearStatus();
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
      _setStatus(AppLocalizations.of(context).musicScrapeApplied);
    } on Object catch (error) {
      if (mounted) {
        _setStatus(
          AppLocalizations.of(
            context,
          ).musicSaveFailed(describeUserFacingError(error).message),
          error: true,
        );
      }
    } finally {
      if (mounted && generation == _scrapeGeneration) {
        setState(() => _scrapeLoading = false);
      }
    }
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

class _EditorBody extends StatelessWidget {
  const _EditorBody({
    required this.track,
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
    required this.statusMessage,
    required this.statusIsError,
  });

  final MusicTrack track;
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
  final String? statusMessage;
  final bool statusIsError;

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

    // AlertDialog(scrollable) 会按 intrinsic 测量内容，LayoutBuilder 无法
    // 参与；窄屏切栈改用屏幕宽度判据（与歌单编辑弹窗同约定）。640 内容宽
    // 加弹窗默认内边距后，760 以下必被收窄，此时退化为纵向堆叠。
    final compact = MediaQuery.sizeOf(context).width < 760;
    final topSection =
        compact
            ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: coverPanel),
                const SizedBox(height: 24),
                formPanel,
              ],
            )
            : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 232, child: coverPanel),
                const SizedBox(width: 28),
                Expanded(child: formPanel),
              ],
            );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        topSection,
        const SizedBox(height: 24),
        lyricsSection,
        if (candidatesSection != null) ...[
          const SizedBox(height: 24),
          candidatesSection,
        ],
        if (statusMessage != null) ...[
          const SizedBox(height: 18),
          _InlineStatus(message: statusMessage!, error: statusIsError),
        ],
      ],
    );
  }
}

/// 弹窗内联反馈行：成功与错误共用同一形态，靠前景色区分。
class _InlineStatus extends StatelessWidget {
  const _InlineStatus({required this.message, required this.error});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          error ? Icons.error_outline_rounded : Icons.check_circle_outline,
          size: 16,
          color: error ? colors.danger : colors.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: error ? colors.danger : colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
