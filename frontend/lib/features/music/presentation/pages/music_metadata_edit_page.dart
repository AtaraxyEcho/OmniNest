import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';

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
    return Scaffold(
      backgroundColor: context.musicColors.surface,
      body: _MetadataEditForm(track: track),
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
  List<MusicScrapeCandidate>? _scrapeCandidates;
  // 封面
  String? _coverFileName;
  List<int>? _coverBytes;
  // 歌词
  String? _lyricsFileName;
  String? _lyricsContent;

  @override
  void initState() {
    super.initState();
    final track = widget.track;
    _titleController = TextEditingController(text: track.title);
    _artistController = TextEditingController(text: track.artistName);
    _albumController = TextEditingController(text: track.albumTitle);
    _genreController = TextEditingController();
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
    final track = widget.track;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditHeader(track: track),
        const SizedBox(height: 24),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final coverPanel = _CoverPanel(track: track);
              final formPanel = _FormPanel(
                titleController: _titleController,
                artistController: _artistController,
                albumController: _albumController,
                genreController: _genreController,
                saving: _saving,
                scrapeLoading: _scrapeLoading,
                coverFileName: _coverFileName,
                lyricsFileName: _lyricsFileName,
                onMatchOnline: _scrapeLoading ? null : _matchOnline,
                onPickCover: _pickCover,
                onPickLyrics: _pickLyrics,
                onCancel: _saving ? null : () => Navigator.of(context).pop(),
                onSave: _saving ? null : _save,
              );
              final candidatesPanel =
                  _scrapeCandidates == null
                      ? null
                      : _ScrapeCandidatesPanel(
                        candidates: _scrapeCandidates!,
                        applying: _scrapeLoading,
                        onApply: _applyCandidate,
                      );
              if (!wide) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      coverPanel,
                      const SizedBox(height: 18),
                      formPanel,
                      if (candidatesPanel != null) ...[
                        const SizedBox(height: 18),
                        candidatesPanel,
                      ],
                    ],
                  ),
                );
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 300, child: coverPanel),
                        const SizedBox(width: 24),
                        Expanded(child: formPanel),
                      ],
                    ),
                    if (candidatesPanel != null) ...[
                      const SizedBox(height: 18),
                      candidatesPanel,
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
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
            genre: _blankToNull(_genreController.text),
            lyricsRaw: _lyricsContent,
            coverBytes: _coverBytes,
            coverFileName: _coverFileName,
          );
      if (mounted) {
        _showMessage(AppLocalizations.of(context).musicMetadataSaved);
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          AppLocalizations.of(context).musicSaveFailed(error.toString()),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
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
        AppLocalizations.of(context).musicSaveFailed(error.toString()),
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
      }
      _showMessage(AppLocalizations.of(context).musicScrapeApplied);
    } on Object catch (error) {
      if (mounted) {
        _showMessage(
          AppLocalizations.of(context).musicSaveFailed(error.toString()),
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (!mounted || generation != _filePickGeneration) {
      return;
    }
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      setState(() {
        _coverFileName = file.name;
        _coverBytes = file.bytes;
      });
    }
  }

  Future<void> _pickLyrics() async {
    final generation = ++_filePickGeneration;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['lrc', 'txt', 'srt', 'vtt'],
      allowMultiple: false,
      withData: true,
    );
    if (!mounted || generation != _filePickGeneration) {
      return;
    }
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      String? content;
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!);
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
  const _EditHeader({required this.track});

  final MusicTrack track;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).musicEditMetadata,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${track.title} — ${track.artistName}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.musicColors.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverPanel extends StatelessWidget {
  const _CoverPanel({required this.track});

  final MusicTrack track;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child:
                  track.coverUrl != null && track.coverUrl!.isNotEmpty
                      ? Image.network(
                        track.coverUrl!,
                        width: 200,
                        height: 200,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, error, stackTrace) =>
                                _placeholderCover(context),
                      )
                      : _placeholderCover(context),
            ),
            const SizedBox(height: 16),
            Text(
              track.title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              track.artistName,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.musicColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              track.albumTitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.musicColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                track.qualityText,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderCover(BuildContext context) {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: 64,
        color: context.musicColors.onSurfaceVariant.withValues(alpha: 0.4),
      ),
    );
  }
}

class _FormPanel extends StatelessWidget {
  const _FormPanel({
    required this.titleController,
    required this.artistController,
    required this.albumController,
    required this.genreController,
    required this.saving,
    required this.scrapeLoading,
    this.coverFileName,
    this.lyricsFileName,
    this.onMatchOnline,
    this.onPickCover,
    this.onPickLyrics,
    this.onCancel,
    this.onSave,
  });

  final TextEditingController titleController;
  final TextEditingController artistController;
  final TextEditingController albumController;
  final TextEditingController genreController;
  final bool saving;
  final bool scrapeLoading;
  final String? coverFileName;
  final String? lyricsFileName;
  final VoidCallback? onMatchOnline;
  final VoidCallback? onPickCover;
  final VoidCallback? onPickLyrics;
  final VoidCallback? onCancel;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).musicEditMetadata,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onMatchOnline,
                  icon:
                      scrapeLoading
                          ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.travel_explore_rounded, size: 18),
                  label: Text(AppLocalizations.of(context).musicScrapeMatch),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _field(
              AppLocalizations.of(context).musicFieldTitle,
              titleController,
              required: true,
            ),
            const SizedBox(height: 16),
            _field(
              AppLocalizations.of(context).musicFieldArtist,
              artistController,
            ),
            const SizedBox(height: 16),
            _field(
              AppLocalizations.of(context).musicFieldAlbum,
              albumController,
            ),
            const SizedBox(height: 16),
            _field(
              AppLocalizations.of(context).musicFieldGenre,
              genreController,
            ),
            const SizedBox(height: 24),
            // 封面上传
            Text(
              AppLocalizations.of(context).musicCoverImage,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onPickCover,
              icon: const Icon(Icons.image_rounded, size: 18),
              label: Text(
                coverFileName != null
                    ? AppLocalizations.of(
                      context,
                    ).musicCoverSelected(coverFileName!)
                    : AppLocalizations.of(context).musicCoverPick,
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // 歌词上传
            Text(
              AppLocalizations.of(context).musicLyricsFile,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onPickLyrics,
              icon: const Icon(Icons.lyrics_rounded, size: 18),
              label: Text(
                lyricsFileName ?? AppLocalizations.of(context).musicLyricsPick,
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: onCancel,
                  child: Text(AppLocalizations.of(context).musicCancel),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: onSave,
                  icon:
                      saving
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.save_rounded),
                  label: Text(
                    saving
                        ? AppLocalizations.of(context).musicSaving
                        : AppLocalizations.of(context).musicSave,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool required = false,
    String? hint,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
      ),
    );
  }
}

/// 在线刮削候选列表，应用后由宿主回填表单字段。
class _ScrapeCandidatesPanel extends StatelessWidget {
  const _ScrapeCandidatesPanel({
    required this.candidates,
    required this.applying,
    required this.onApply,
  });

  final List<MusicScrapeCandidate> candidates;
  final bool applying;
  final ValueChanged<MusicScrapeCandidate> onApply;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      elevation: 0,
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.musicScrapeCandidatesTitle,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (candidates.isEmpty)
              Text(
                l10n.musicScrapeNoCandidates,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.musicColors.onSurfaceVariant,
                ),
              )
            else
              for (final candidate in candidates)
                _ScrapeCandidateCard(
                  candidate: candidate,
                  applying: applying,
                  onApply: () => onApply(candidate),
                ),
          ],
        ),
      ),
    );
  }
}

class _ScrapeCandidateCard extends StatelessWidget {
  const _ScrapeCandidateCard({
    required this.candidate,
    required this.applying,
    required this.onApply,
  });

  final MusicScrapeCandidate candidate;
  final bool applying;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.musicColors.outline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${candidate.artistName} · ${candidate.albumTitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.musicColors.onSurfaceVariant,
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
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              chip,
                              style: Theme.of(
                                context,
                              ).textTheme.labelSmall?.copyWith(
                                color: context.musicColors.onSurfaceVariant,
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
              child: Text(l10n.musicScrapeApply),
            ),
          ],
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
