import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_deck_search_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';
import 'package:omninest/features/music/presentation/widgets/music_playback_controls.dart';

/// 桌面端 Music Deck 搜索输入框。
class MusicDeckSearchField extends StatelessWidget {
  const MusicDeckSearchField({
    required this.controller,
    required this.focusNode,
    required this.sources,
    required this.onChanged,
    required this.onFocusChanged,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Set<MusicPlatform> sources;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onFocusChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.globalColors;
    return Focus(
      onFocusChange: onFocusChanged,
      child: DecoratedBox(
        key: const ValueKey<String>('music-global-search-surface'),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.42),
          ),
        ),
        child: SizedBox(
          height: 42,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: AppTypography.bodyMedium,
            ),
            decoration: InputDecoration(
              hintText: l10n.musicSearchHint,
              hintStyle: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: AppTypography.bodyMedium,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 19,
                color: colors.onSurfaceVariant,
              ),
              suffixIcon:
                  controller.text.isEmpty
                      ? null
                      : IconButton(
                        tooltip: l10n.musicClose,
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                        icon: const Icon(Icons.close_rounded, size: 17),
                      ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 11),
            ),
          ),
        ),
      ),
    );
  }
}

/// 桌面端搜索结果浮层，只按来源分组歌曲。
class MusicDeckSearchOverlay extends ConsumerWidget {
  const MusicDeckSearchOverlay({required this.onDismiss, super.key});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = ref.watch(musicDeckSearchProvider);
    if (!search.visible) {
      return const SizedBox.shrink();
    }
    final orderedSources = MusicPlatform.values.where(
      (source) => search.sources.contains(source),
    );
    return MusicDeckGlass(
      opacity: 0.3,
      blur: 18,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 500),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final source in orderedSources)
              _SearchSourceGroup(
                source: source,
                items: search.results[source] ?? const <MusicPlayableItem>[],
                loading: search.loadingSources.contains(source),
                failure: search.failures[source],
                onPlay: (items, index) {
                  ref
                      .read(musicCenterControllerProvider.notifier)
                      .playItems(items, startIndex: index);
                  onDismiss();
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// 移动端全屏歌曲搜索页面。
class MusicDeckMobileSearchPage extends ConsumerStatefulWidget {
  const MusicDeckMobileSearchPage({super.key});

  @override
  ConsumerState<MusicDeckMobileSearchPage> createState() =>
      _MusicDeckMobileSearchPageState();
}

class _MusicDeckMobileSearchPageState
    extends ConsumerState<MusicDeckMobileSearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Set<MusicPlatform> _sources = <MusicPlatform>{MusicPlatform.local};

  @override
  void initState() {
    super.initState();
    final platforms =
        ref
            .read(musicPlatformLibraryProvider)
            .asData
            ?.value
            .connectedStatuses ??
        const [];
    _sources = <MusicPlatform>{
      MusicPlatform.local,
      for (final status in platforms)
        MusicPlatform.fromApiValue(status.platform),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final search = ref.watch(musicDeckSearchProvider);
    return Scaffold(
      backgroundColor: const Color(0xF20A1218),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _updateQuery,
          style: TextStyle(color: context.musicColors.onSurface),
          decoration: InputDecoration(
            hintText: l10n.musicSearchHint,
            border: InputBorder.none,
            hintStyle: TextStyle(color: context.musicColors.onSurfaceVariant),
          ),
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final source in _availableSources())
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: _sources.contains(source),
                      label: MusicDeckSourceBadge(platform: source),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _sources = <MusicPlatform>{..._sources, source};
                          } else {
                            _sources = <MusicPlatform>{..._sources}
                              ..remove(source);
                          }
                        });
                        _updateQuery(_controller.text);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child:
                !search.visible
                    ? Center(
                      child: Text(
                        l10n.musicDeckSearchPrompt,
                        style: TextStyle(
                          color: context.musicColors.onSurfaceVariant,
                        ),
                      ),
                    )
                    : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
                      children: [
                        for (final source in _availableSources())
                          if (_sources.contains(source))
                            _SearchSourceGroup(
                              source: source,
                              items:
                                  search.results[source] ??
                                  const <MusicPlayableItem>[],
                              loading: search.loadingSources.contains(source),
                              failure: search.failures[source],
                              onPlay: (items, index) {
                                ref
                                    .read(
                                      musicCenterControllerProvider.notifier,
                                    )
                                    .playItems(items, startIndex: index);
                                Navigator.of(context).pop();
                              },
                            ),
                      ],
                    ),
          ),
        ],
      ),
    );
  }

  List<MusicPlatform> _availableSources() {
    final statuses =
        ref
            .watch(musicPlatformLibraryProvider)
            .asData
            ?.value
            .connectedStatuses ??
        const [];
    return <MusicPlatform>[
      MusicPlatform.local,
      for (final status in statuses)
        MusicPlatform.fromApiValue(status.platform),
    ];
  }

  void _updateQuery(String query) {
    ref.read(musicDeckSearchProvider.notifier).updateQuery(query, _sources);
  }
}

class _SearchSourceGroup extends StatelessWidget {
  const _SearchSourceGroup({
    required this.source,
    required this.items,
    required this.loading,
    required this.onPlay,
    this.failure,
  });

  final MusicPlatform source;
  final List<MusicPlayableItem> items;
  final bool loading;
  final String? failure;
  final void Function(List<MusicPlayableItem> items, int index) onPlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                MusicDeckSourceBadge(platform: source),
                const Spacer(),
                if (loading)
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
              ],
            ),
          ),
          if (failure != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Text(
                failure!,
                style: const TextStyle(
                  color: Color(0xFFFFB4AB),
                  fontSize: AppTypography.bodySmall,
                ),
              ),
            )
          else if (!loading && items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Text(
                l10n.musicDeckNoSearchResults,
                style: TextStyle(
                  color: context.musicColors.onSurfaceVariant,
                  fontSize: AppTypography.bodySmall,
                ),
              ),
            )
          else
            for (var index = 0; index < items.length.clamp(0, 8); index++)
              _SearchTrackRow(
                item: items[index],
                onTap: () => onPlay(items, index),
              ),
        ],
      ),
    );
  }
}

class _SearchTrackRow extends StatelessWidget {
  const _SearchTrackRow({required this.item, required this.onTap});

  final MusicPlayableItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final track = item.track;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        minTileHeight: 54,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        onTap: onTap,
        leading: SizedBox.square(
          dimension: 40,
          child: MusicDeckArtwork(title: track.title, imageUrl: track.coverUrl),
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.musicColors.onSurface,
            fontSize: AppTypography.bodyMedium,
          ),
        ),
        subtitle: Text(
          '${track.artistName} · ${track.albumTitle}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.musicColors.onSurfaceVariant,
            fontSize: AppTypography.labelSmall,
          ),
        ),
        trailing: MusicPlaybackButton(
          isPlaying: false,
          tooltip: AppLocalizations.of(context).musicPlay,
          onPressed: onTap,
          buttonSize: MusicPlaybackButtonSize.inline,
        ),
      ),
    );
  }
}
