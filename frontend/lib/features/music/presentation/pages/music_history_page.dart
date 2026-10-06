import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_backdrop_theme.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/app/theme/mobile_env_colors.dart';
import 'package:omninest/core/errors/user_facing_error_l10n.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/mobile_sample_kit.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_history_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';

/// 音乐播放历史页面，按日期分组展示并支持触底加载。
class MusicHistoryPage extends ConsumerStatefulWidget {
  const MusicHistoryPage({super.key});

  @override
  ConsumerState<MusicHistoryPage> createState() => _MusicHistoryPageState();
}

class _MusicHistoryPageState extends ConsumerState<MusicHistoryPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(ref.read(musicHistoryControllerProvider.notifier).refresh());
    });
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(musicHistoryControllerProvider);
    final l10n = AppLocalizations.of(context);
    if (MobileShellScope.isHosted(context)) {
      return MobilePageSurface(
        backdropOpacity: 0.92,
        child: history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error:
              (error, stackTrace) =>
                  _hostedHistoryFailure(context, '$error', l10n),
          data: (state) {
            if (state.errorMessage != null) {
              return _hostedHistoryFailure(
                context,
                l10n.localizeStoredError(state.errorMessage!),
                l10n,
              );
            }
            return Column(
              children: [
                MobileModuleHeader(
                  title: l10n.musicHistoryTitle,
                  subtitle: l10n.musicDeckTrackCount(_historyEntryCount(state)),
                  backTooltip:
                      MaterialLocalizations.of(context).backButtonTooltip,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child:
                      state.groups.isEmpty
                          ? ListView(
                            padding: EdgeInsets.zero,
                            children: [
                              EnvEmptyState(
                                icon: OmniIcons.clock,
                                title: l10n.musicHistoryEmpty,
                              ),
                            ],
                          )
                          : _HistoryList(state: state),
                ),
              ],
            );
          },
        ),
      );
    }
    return Theme(
      data: MusicBackdropTheme.withNeutralTextButtons(Theme.of(context)),
      child: Scaffold(
        backgroundColor: context.musicColors.surface,
        body: history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => _HistoryFailure(message: '$error'),
          data: (state) {
            if (state.errorMessage != null) {
              return _HistoryFailure(
                message: l10n.localizeStoredError(state.errorMessage!),
              );
            }
            return Column(
              children: [
                _HistoryHeader(
                  title: l10n.musicHistoryTitle,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child:
                      state.groups.isEmpty
                          ? Center(
                            child: Text(
                              l10n.musicHistoryEmpty,
                              style: TextStyle(
                                color: context.musicColors.onSurfaceVariant,
                              ),
                            ),
                          )
                          : _HistoryList(state: state),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  int _historyEntryCount(MusicHistoryState state) {
    return state.groups.fold<int>(
      0,
      (total, group) => total + group.entries.length,
    );
  }

  /// 托管态失败面：与空态同族的环境空态 + 重试行动（样例 .empty-action）。
  Widget _hostedHistoryFailure(
    BuildContext context,
    String message,
    AppLocalizations l10n,
  ) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        EnvEmptyState(
          icon: OmniIcons.clock,
          title: l10n.musicHistoryTitle,
          message: message,
          actionLabel: l10n.coreRetry,
          onAction:
              () => unawaited(
                ref.read(musicHistoryControllerProvider.notifier).refresh(),
              ),
        ),
      ],
    );
  }
}

class _HistoryList extends ConsumerStatefulWidget {
  const _HistoryList({required this.state});

  final MusicHistoryState state;

  @override
  ConsumerState<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends ConsumerState<_HistoryList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels <= 480) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(musicHistoryControllerProvider.notifier).loadMore();
      });
    }
  }

  /// 内容不足一屏时主动补齐下一页，保证触底加载可达。
  void _maybeFillViewport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      if (position.maxScrollExtent < position.viewportDimension) {
        ref.read(musicHistoryControllerProvider.notifier).loadMore();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final l10n = AppLocalizations.of(context);
    final hosted = MobileShellScope.isHosted(context);
    if (state.hasMore && !state.loadingMore) {
      _maybeFillViewport();
    }

    final rows = <Widget>[
      for (final group in state.groups) ...[
        if (hosted)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
            child: MobileEnvSectionHeader(title: _dayLabel(context, group)),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
            child: Text(
              _dayLabel(context, group),
              style: TextStyle(
                color: context.musicColors.onSurface,
                fontSize: AppTypography.titleMedium,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        for (final entry in group.entries)
          if (hosted)
            SampleSerifRow(
              number: _historyEntryTime(entry),
              title: entry.title,
              subtitle: entry.artistName,
              onTap: () => _playEntry(context, ref, entry),
            )
          else
            _HistoryRow(
              entry: entry,
              onPlay: () => _playEntry(context, ref, entry),
            ),
      ],
    ];
    if (state.loadingMore) {
      rows.add(
        Padding(
          padding: EdgeInsets.symmetric(vertical: hosted ? 20 : 16),
          child: Center(
            child: SizedBox.square(
              dimension: hosted ? 22 : 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: hosted ? MobileEnvColors.inkMuted : null,
              ),
            ),
          ),
        ),
      );
    } else if (state.hasMore) {
      rows.add(
        Padding(
          padding: EdgeInsets.symmetric(vertical: hosted ? 16 : 8),
          child: Center(
            child: TextButton(
              onPressed:
                  () =>
                      ref
                          .read(musicHistoryControllerProvider.notifier)
                          .loadMore(),
              style:
                  hosted
                      ? TextButton.styleFrom(
                        foregroundColor: MobileEnvColors.inkMuted,
                        minimumSize: const Size(0, 38),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      )
                      : null,
              child: Text(l10n.musicHistoryLoadMore),
            ),
          ),
        ),
      );
    }
    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.only(bottom: hosted ? 96 : 48),
      children: rows,
    );
  }

  String _dayLabel(BuildContext context, MusicHistoryDayGroup group) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(
      group.dayKey.year,
      group.dayKey.month,
      group.dayKey.day,
    );
    final diffDays = today.difference(day).inDays;
    if (diffDays == 0) {
      return l10n.musicHistoryToday;
    }
    if (diffDays == 1) {
      return l10n.musicHistoryYesterday;
    }
    final label =
        '${group.dayKey.year}-${group.dayKey.month.toString().padLeft(2, '0')}-${group.dayKey.day.toString().padLeft(2, '0')}';
    return label;
  }

  void _playEntry(
    BuildContext context,
    WidgetRef ref,
    MusicPlayHistoryEntry entry,
  ) {
    final key = entry.playableKey;
    if (key.startsWith('local:')) {
      final trackId = key.substring('local:'.length);
      final center = ref.read(musicCenterControllerProvider).asData?.value;
      final track = center?.tracks.where((t) => t.id == trackId).firstOrNull;
      if (track != null && context.mounted) {
        ref.read(musicCenterControllerProvider.notifier).playTrack(track);
      }
      return;
    }
    // 在线曲目缺少平台凭据快照，从可播放对象构造兜底卡片。
    final segments = key.split(':');
    if (segments.length == 3) {
      final online = OnlineTrack(
        platform: segments[1],
        songId: segments[2],
        title: entry.title,
        artistName: entry.artistName,
        albumTitle: entry.albumTitle ?? '',
        coverUrl: entry.coverUrl ?? '',
      );
      ref.read(musicCenterControllerProvider.notifier).playOnlineTrack(online);
    }
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.onPlay});

  final MusicPlayHistoryEntry entry;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final time = _historyEntryTime(entry);
    final isLocal = entry.playableKey.startsWith('local:');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: SizedBox.square(
        dimension: 44,
        child: MusicDeckArtwork(
          title: entry.title,
          imageUrl: entry.listCoverUrl,
        ),
      ),
      title: Text(
        entry.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.onSurface),
      ),
      subtitle: Text(
        entry.artistName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLocal ||
              MusicPlatform.values.any(
                (platform) => platform.apiValue == entry.platform,
              ))
            MusicDeckSourceBadge(
              platform:
                  isLocal
                      ? MusicPlatform.local
                      : MusicPlatform.fromApiValue(entry.platform ?? ''),
            ),
          const SizedBox(width: 12),
          Text(
            time,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: AppTypography.labelSmall,
            ),
          ),
        ],
      ),
      onTap: onPlay,
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 24, 16, 8),
      child: Row(
        children: [
          IconButton(
            // 返回钮只有字形，样例每个图标钮都带 aria-label：tooltip 同时
            // 供悬停提示与读屏播报。
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: onBack,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryFailure extends StatelessWidget {
  const _HistoryFailure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.musicColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 播放时刻的 24 小时短标签（托管行与工位行同源）。
String _historyEntryTime(MusicPlayHistoryEntry entry) {
  final hour = entry.playedAt.hour.toString().padLeft(2, '0');
  final minute = entry.playedAt.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
