import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover_field.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/video/video_dashboard.dart';

/// 影视详情概览页的动作行（样例 `MovieDetail.tsx:87-89` 的 `.row-actions`）。
///
/// 四个动作全部走已有后端能力：编辑详情写 `PUT /admin/video/items/{id}/metadata`、
/// 匹配元数据先取候选再按选中条目创建刮削任务、重新探测同步跑 FFprobe、
/// 导出 NFO 落盘派生资产。执行成功后失效详情 provider，页面自行重取。
class DesktopMovieDetailActions extends ConsumerStatefulWidget {
  const DesktopMovieDetailActions({required this.item, super.key});

  final MovieVideoItem item;

  @override
  ConsumerState<DesktopMovieDetailActions> createState() =>
      _DesktopMovieDetailActionsState();
}

class _DesktopMovieDetailActionsState
    extends ConsumerState<DesktopMovieDetailActions> {
  bool _probing = false;
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        DesktopButton(
          label: l10n.desktopMoviesEditDetails,
          icon: DesktopIcons.edit,
          variant: DesktopButtonVariant.soft,
          onPressed: () => unawaited(_editMetadata()),
        ),
        DesktopButton(
          label:
              _scraped
                  ? l10n.desktopMoviesRematchMetadata
                  : l10n.desktopMoviesMatchMetadata,
          icon: DesktopIcons.sparkle,
          variant: DesktopButtonVariant.soft,
          onPressed: () => unawaited(_matchMetadata()),
        ),
        DesktopButton(
          label: l10n.desktopMoviesReprobe,
          icon: DesktopIcons.retry,
          variant: DesktopButtonVariant.soft,
          busy: _probing,
          onPressed: _probing ? null : () => unawaited(_reprobe()),
        ),
        DesktopButton(
          label: l10n.desktopMoviesExportNfo,
          icon: DesktopIcons.download,
          variant: DesktopButtonVariant.soft,
          busy: _exporting,
          onPressed: _exporting ? null : () => unawaited(_exportNfo()),
        ),
      ],
    );
  }

  /// 样例以「是否已完成刮削」决定按钮文案：PENDING / FAILED 视为未刮削。
  bool get _scraped {
    final status = widget.item.metadataStatus.toUpperCase();
    return status == 'MATCHED' || status == 'MANUAL';
  }

  Future<void> _editMetadata() async {
    await showDesktopMovieMetadataDialog(context, widget.item);
  }

  Future<void> _matchMetadata() async {
    await showDesktopMovieMatchDialog(context, widget.item);
  }

  Future<void> _reprobe() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _probing = true);
    try {
      await ref.read(movieDetailBackendActionsProvider).reprobe(widget.item.id);
      if (!mounted) return;
      ref.invalidate(movieDetailProvider(widget.item.id));
      showDesktopToast(
        context,
        l10n.desktopMoviesProbeDone,
        kind: DesktopToastKind.success,
        icon: DesktopIcons.check,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.desktopMoviesReprobe, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _probing = false);
      }
    }
  }

  Future<void> _exportNfo() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _exporting = true);
    try {
      final export = await ref
          .read(movieDetailBackendActionsProvider)
          .exportNfo(widget.item.id);
      if (!mounted) return;
      ref.invalidate(movieDetailProvider(widget.item.id));
      showDesktopToast(
        context,
        export.exportPath.isEmpty
            ? l10n.desktopMoviesNfoExported
            : '${l10n.desktopMoviesNfoExported} · ${export.exportPath}',
        kind: DesktopToastKind.success,
        icon: DesktopIcons.download,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.desktopMoviesExportNfo, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }
}

/// 元数据编辑弹窗：海报 / 标题 / 类型 / 年份 / 时长 / 评分 / 演员 / 简介，保存后回写详情。
Future<void> showDesktopMovieMetadataDialog(
  BuildContext context,
  MovieVideoItem item,
) {
  return showDesktopDrawer<void>(
    context,
    width: 520,
    builder: (dialogContext) => _MetadataEditDialog(item: item),
  );
}

/// 匹配候选弹窗：列出提供器搜索结果，选中后按该条目创建刮削任务。
Future<void> showDesktopMovieMatchDialog(
  BuildContext context,
  MovieVideoItem item,
) {
  return showDesktopDialog<void>(
    context,
    builder: (dialogContext) => _MatchCandidatesDialog(item: item),
  );
}

class _MetadataEditDialog extends ConsumerStatefulWidget {
  const _MetadataEditDialog({required this.item});

  final MovieVideoItem item;

  @override
  ConsumerState<_MetadataEditDialog> createState() =>
      _MetadataEditDialogState();
}

class _MetadataEditDialogState extends ConsumerState<_MetadataEditDialog> {
  late final TextEditingController _title;
  late final TextEditingController _year;
  late final TextEditingController _runtime;
  late final TextEditingController _overview;
  late final TextEditingController _genre;
  late final TextEditingController _rating;
  late final TextEditingController _cast;
  late final TextEditingController _posterUrl;
  late final String _initialPosterUrl;
  DesktopPickedCover? _pickedPoster;
  bool _clearPoster = false;
  bool _saving = false;
  String? _posterUrlError;

  bool get _canRestoreOriginal =>
      widget.item.metadata['manualMetadataOriginal'] is Map;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _title = TextEditingController(text: item.title);
    _year = TextEditingController(
      text: item.releaseDate?.year.toString() ?? '',
    );
    _runtime = TextEditingController(
      text:
          item.runtimeSeconds != null && item.runtimeSeconds! > 0
              ? _formatRuntime(item.runtimeSeconds!)
              : '',
    );
    _overview = TextEditingController(text: item.overview ?? '');
    _genre = TextEditingController(text: item.genres.join(', '));
    _rating = TextEditingController(
      text: item.rating?.toStringAsFixed(1) ?? '',
    );
    _cast = TextEditingController(
      text: item.castMembers.map((member) => member.name).join(', '),
    );
    final storedPosterUrl = item.metadata['manualPosterUrl']?.toString().trim();
    final externalPosterUrl =
        item.posterFileId == null &&
                item.posterUrl != null &&
                _isHttpUrl(item.posterUrl!.trim())
            ? item.posterUrl!.trim()
            : null;
    _posterUrl = TextEditingController(
      text:
          (storedPosterUrl != null && storedPosterUrl.isNotEmpty)
              ? storedPosterUrl
              : (externalPosterUrl ?? ''),
    );
    _initialPosterUrl = _posterUrl.text;
  }

  @override
  void dispose() {
    _title.dispose();
    _year.dispose();
    _runtime.dispose();
    _overview.dispose();
    _genre.dispose();
    _rating.dispose();
    _cast.dispose();
    _posterUrl.dispose();
    super.dispose();
  }

  void _onFieldChanged(String _) => setState(() {});

  bool get _yearValid {
    final text = _year.text.trim();
    return text.isEmpty || RegExp(r'^\d{4}$').hasMatch(text);
  }

  bool get _ratingValid {
    final text = _rating.text.trim();
    if (text.isEmpty) return true;
    final value = double.tryParse(text);
    return value != null && value.isFinite && value >= 0 && value <= 10;
  }

  bool get _canSave =>
      _title.text.trim().isNotEmpty && _yearValid && _ratingValid;

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final title = _title.text.trim();
    if (!_canSave || _saving) {
      return;
    }
    final yearText = _year.text.trim();
    final year = yearText.isEmpty ? null : int.tryParse(yearText);
    final runtimeText = _runtime.text.trim();
    final runtimeSeconds = _parseRuntime(runtimeText);
    final ratingText = _rating.text.trim();
    final rating = ratingText.isEmpty ? null : double.tryParse(ratingText);
    final posterUrl = _posterUrl.text.trim();

    if (runtimeText.isNotEmpty && runtimeSeconds == null) {
      showDesktopToast(
        context,
        l10n.videoMetaRuntimeInvalid,
        kind: DesktopToastKind.warn,
        icon: DesktopIcons.info,
      );
      return;
    }
    if (_pickedPoster == null &&
        !_clearPoster &&
        posterUrl.isNotEmpty &&
        !_isHttpUrl(posterUrl)) {
      setState(() => _posterUrlError = l10n.videoMetaPosterUrlInvalid);
      return;
    }
    setState(() {
      _posterUrlError = null;
      _saving = true;
    });
    try {
      final commands = ref.read(movieMetadataCommandsProvider);
      String? uploadedPosterFileId;
      if (_pickedPoster != null) {
        uploadedPosterFileId = await commands.uploadPoster(
          bytes: _pickedPoster!.bytes,
          fileName: _pickedPoster!.fileName,
        );
      }
      final shouldClearPoster = _clearPoster && uploadedPosterFileId == null;
      final posterUrlChanged = posterUrl != _initialPosterUrl.trim();
      await commands.updateMetadata(
        videoItemId: widget.item.id,
        title: title,
        originalTitle: widget.item.originalTitle,
        releaseDate: year != null ? DateTime(year) : widget.item.releaseDate,
        overview: _overview.text.trim(),
        posterFileId:
            shouldClearPoster
                ? null
                : (uploadedPosterFileId ?? widget.item.posterFileId),
        backdropFileId: widget.item.backdropFileId,
        runtimeSeconds:
            runtimeText.isEmpty
                ? null
                : runtimeSeconds ?? widget.item.runtimeSeconds,
        clearRuntime: runtimeText.isEmpty,
        clearPoster: shouldClearPoster,
        genres: _splitCommaSeparated(_genre.text),
        rating: rating,
        cast: _splitCommaSeparated(_cast.text),
        posterUrl:
            !shouldClearPoster &&
                    uploadedPosterFileId == null &&
                    posterUrlChanged
                ? posterUrl
                : null,
        metadataStatus: widget.item.metadataStatus,
      );
      ref.invalidate(movieDetailProvider(widget.item.id));
      if (!mounted) {
        return;
      }
      unawaited(
        ref.read(movieCenterControllerProvider.notifier).refreshForRealtime(),
      );
      showDesktopToast(
        context,
        l10n.videoMetadataSaved,
        kind: DesktopToastKind.success,
        icon: DesktopIcons.check,
      );
      closeDesktopModal(context);
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.videoDetailEdit, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  static String _formatRuntime(int runtimeSeconds) {
    final minutes = (runtimeSeconds / 60).round();
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return hours == 0 ? '${remainder}m' : '${hours}h ${remainder}m';
  }

  static int? _parseRuntime(String input) {
    final value = input.trim().toLowerCase();
    if (value.isEmpty) return null;
    final match = RegExp(
      r'^(?:(\d+)\s*h)?\s*(?:(\d+)\s*m)?$',
    ).firstMatch(value);
    if (match != null && (match.group(1) != null || match.group(2) != null)) {
      final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
      final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
      final totalMinutes = hours * 60 + minutes;
      return totalMinutes > 0 ? totalMinutes * 60 : null;
    }
    final minutes = int.tryParse(value);
    return minutes == null || minutes <= 0 ? null : minutes * 60;
  }

  static List<String> _splitCommaSeparated(String value) =>
      value
          .split(',')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toSet()
          .toList();

  static bool _isHttpUrl(String value) {
    if (value.length > 2048) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme.toLowerCase() == 'http' ||
            uri.scheme.toLowerCase() == 'https') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  Future<void> _restoreOriginal() async {
    if (_saving || !_canRestoreOriginal) return;
    final item = widget.item;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(movieMetadataCommandsProvider)
          .updateMetadata(
            videoItemId: item.id,
            title: _title.text.trim().isEmpty ? item.title : _title.text.trim(),
            restoreOriginal: true,
          );
      if (!mounted) return;
      ref.invalidate(movieDetailProvider(item.id));
      unawaited(
        ref.read(movieCenterControllerProvider.notifier).refreshForRealtime(),
      );
      showDesktopToast(
        context,
        l10n.readerMetadataRestored,
        kind: DesktopToastKind.success,
        icon: DesktopIcons.undo,
      );
      closeDesktopModal(context, true);
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.videoDetailEdit, error),
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
      eyebrow: l10n.videoMetaEyebrow,
      title: l10n.videoMetaEditDetails,
      footer: Row(
        children: [
          if (_canRestoreOriginal)
            DesktopButton(
              label: l10n.readerRestoreOriginalMetadata,
              icon: DesktopIcons.undo,
              onPressed: _saving ? null : () => unawaited(_restoreOriginal()),
            ),
          const Spacer(),
          DesktopButton(
            label: l10n.coreCancel,
            onPressed: _saving ? null : () => closeDesktopModal(context),
          ),
          const SizedBox(width: 10),
          DesktopButton(
            label: l10n.coreSave,
            variant: DesktopButtonVariant.primary,
            busy: _saving,
            onPressed: _saving || !_canSave ? null : () => unawaited(_save()),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopCoverField(
            label: l10n.videoMetaFieldPosterUrl,
            shape: DesktopCoverFieldShape.poster,
            previewUrl: widget.item.posterImageUrl,
            fallbackIcon: DesktopIcons.film,
            urlController: _posterUrl,
            pickedCover: _pickedPoster,
            cleared: _clearPoster,
            urlError: _posterUrlError,
            enabled: !_saving,
            onPicked: (picked) {
              setState(() {
                _pickedPoster = picked;
                _clearPoster = false;
                _posterUrlError = null;
              });
            },
            onClear: () {
              setState(() {
                _pickedPoster = null;
                _clearPoster = true;
                _posterUrlError = null;
              });
            },
            onUrlChanged: (_) {
              setState(() {
                _pickedPoster = null;
                _clearPoster = false;
                _posterUrlError = null;
              });
            },
          ),
          const SizedBox(height: 16),
          DesktopTextField(
            controller: _title,
            label: l10n.videoMetaFieldTitle,
            required: true,
            error: _title.text.trim().isEmpty ? l10n.videoTitleRequired : null,
            autofocus: true,
            onChanged: _onFieldChanged,
          ),
          const SizedBox(height: 14),
          DesktopTextField(
            controller: _genre,
            label: l10n.videoMetaFieldGenre,
            hint: l10n.videoMetaCommaSeparated,
            onChanged: _onFieldChanged,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 8,
                child: DesktopTextField(
                  controller: _year,
                  label: l10n.videoMetaFieldYear,
                  hint: '2024',
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  error: _yearValid ? null : 'YYYY',
                  onChanged: _onFieldChanged,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 14,
                child: DesktopTextField(
                  controller: _runtime,
                  label: l10n.videoMetaFieldRuntime,
                  hint: '2h 14m',
                  onChanged: _onFieldChanged,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 8,
                child: DesktopTextField(
                  controller: _rating,
                  label: l10n.videoMetaFieldRating,
                  hint: '8.0',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  error: _ratingValid ? null : '0.0 – 10.0',
                  onChanged: _onFieldChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DesktopTextField(
            controller: _cast,
            label: l10n.videoMetaFieldCast,
            hint: l10n.videoMetaCommaSeparated,
            onChanged: _onFieldChanged,
          ),
          const SizedBox(height: 14),
          DesktopTextField(
            controller: _overview,
            label: l10n.videoMetaFieldSynopsis,
            maxLines: 5,
            height: 124,
            onChanged: _onFieldChanged,
          ),
          const SizedBox(height: 14),
          Text(
            l10n.videoMetadataScopeNote,
            style: DesktopType.caption(skin.text3),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _MatchCandidatesDialog extends ConsumerWidget {
  const _MatchCandidatesDialog({required this.item});

  final MovieVideoItem item;

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    VideoScrapeCandidate candidate,
  ) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(movieDetailBackendActionsProvider)
          .matchCandidate(
            fileNodeId: item.fileNodeId,
            provider: candidate.provider,
            externalId: candidate.externalId,
          );
      if (!context.mounted) {
        return;
      }
      ref.invalidate(movieScrapeCandidatesProvider(item.fileNodeId));
      showDesktopToast(
        context,
        l10n.desktopMoviesMatchQueued,
        icon: DesktopIcons.sparkle,
      );
      closeDesktopModal(context);
    } on Object catch (error) {
      if (context.mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.desktopMoviesMatchMetadata, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final candidates = ref.watch(
      movieScrapeCandidatesProvider(item.fileNodeId),
    );
    return DesktopDialog(
      eyebrow: l10n.desktopMoviesMatchMetadata,
      title: l10n.desktopMoviesMatchTitle,
      width: 560,
      content: candidates.when(
        loading:
            () => Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                l10n.desktopMoviesMatchLoading,
                style: DesktopType.body(skin.text3),
              ),
            ),
        error:
            (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                failureToast(l10n, l10n.desktopMoviesMatchMetadata, error),
                style: DesktopType.body(skin.text3),
              ),
            ),
        data: (items) {
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                l10n.desktopMoviesMatchEmpty,
                style: DesktopType.body(skin.text3),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final candidate in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _CandidateRow(
                    candidate: candidate,
                    onTap: () => unawaited(_apply(context, ref, candidate)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({required this.candidate, required this.onTap});

  final VideoScrapeCandidate candidate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final subtitle = [
      if (candidate.year != null) '${candidate.year}',
      if (candidate.provider.isNotEmpty) candidate.provider,
      if (candidate.externalId.isNotEmpty) '#${candidate.externalId}',
    ].join(' · ');
    return DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: DesktopMotion.fast,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: hovered ? skin.raise2 : skin.raise,
                borderRadius: BorderRadius.circular(DesktopMetrics.radiusSmall),
                border: Border.all(color: skin.line),
              ),
              child: Row(
                children: [
                  Icon(DesktopIcons.film, size: 16, color: skin.text3),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          candidate.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesktopType.rowTitle(skin.text),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.caption(skin.text3),
                          ),
                      ],
                    ),
                  ),
                  if (candidate.voteAverage != null) ...[
                    const SizedBox(width: 8),
                    DesktopChip(
                      candidate.voteAverage!.toStringAsFixed(1),
                      tone: skin.warm,
                    ),
                  ],
                ],
              ),
            ),
          ),
    );
  }
}
