import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/infinite_scroll.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/video/domain/movie_detail_routes.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_empty_state.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_history_row.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_section_header.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_time.dart';

/// 新版观看历史区：标题 + 清空入口 + 缩略图行列表。
class HistorySection extends StatelessWidget {
  const HistorySection({
    required this.items,
    this.onDelete,
    this.onClearAll,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.onLoadMore,
    super.key,
  });

  final List<MovieWatchHistory> items;
  final ValueChanged<MovieWatchHistory>? onDelete;
  final VoidCallback? onClearAll;

  /// 滚动加载三件套：分页后每页行数受控，行容器保持 Column 构建。
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.movieRedesign;
    return InfiniteScrollTrigger(
      enabled: hasMore && !isLoadingMore && onLoadMore != null,
      onLoadMore: onLoadMore ?? () {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: MovieRedesignSectionHeader(
                  title: l10n.videoSectionHistory,
                  subtitleEn: l10n.videoRedesignSubHistory,
                  count: items.isEmpty ? null : items.length,
                  subtitle: l10n.videoHistorySubtitle,
                ),
              ),
              if (onClearAll != null && items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onClearAll,
                      borderRadius: MovieRedesignPalette.borderRadius,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          l10n.videoClearHistory,
                          style: context.movieRedesignText.mono(
                            size: 12,
                            color: palette.mutedForeground,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (items.isEmpty)
            // 分区 Column 为左对齐布局，空状态需撑满宽度才能与
            // Sliver 分区一样水平居中。
            Center(
              child: MovieRedesignEmptyState(
                icon: Icons.manage_history_rounded,
                title: l10n.videoNoWatchHistory,
                subtitle: l10n.videoRedesignNoHistoryHint,
              ),
            )
          else
            MovieRedesignHistoryList(
              entries: [
                for (final item in items)
                  MovieRedesignHistoryEntry(
                    videoItemId: item.videoItemId,
                    title: item.title,
                    subtitle: movieHistoryDurationLabel(item),
                    timeText: movieRedesignRelativeTime(context, item.playedAt),
                    progressText: movieHistoryProgressLabel(item),
                    thumbUrl: item.posterUrl,
                    onTap:
                        item.videoItemId.isEmpty
                            ? null
                            : () => context.push(
                              movieDetailRouteFromIds(
                                videoItemId: item.videoItemId,
                                seriesId: item.seriesId,
                              ),
                            ),
                    onDelete: onDelete == null ? null : () => onDelete!(item),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

String movieHistoryDurationLabel(MovieWatchHistory item) {
  final duration = movieRedesignFormatDuration(item.durationSeconds);
  if (duration.isEmpty) {
    return item.completed ? '100%' : '';
  }
  return duration;
}

String movieHistoryProgressLabel(MovieWatchHistory item) {
  if (item.completed) {
    return '100%';
  }
  return '${item.progressPercent.round()}%';
}

/// 观看历史的托管形态（原型工具页 `.feature-list` 行族）：环境眉标 +
/// 发丝线行（42 图标舱 + 名称/明细 + 行内动作），删除走 `.recycle-actions`
/// 同式的 38 行内钮，不额外开编辑态。
class HostedHistorySection extends StatelessWidget {
  const HostedHistorySection({
    required this.items,
    this.onDelete,
    this.onClearAll,
    this.isLoadingMore = false,
    super.key,
  });

  final List<MovieWatchHistory> items;
  final ValueChanged<MovieWatchHistory>? onDelete;
  final VoidCallback? onClearAll;
  final bool isLoadingMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MobileEnvSectionHeader(
          title: l10n.videoSectionHistory,
          eyebrow: l10n.videoHistorySubtitle,
          action:
              onClearAll == null || items.isEmpty
                  ? null
                  : MobileEnvInlineIconButton(
                    tooltip: l10n.videoClearHistory,
                    icon: Icons.delete_sweep_outlined,
                    onTap: onClearAll!,
                  ),
        ),
        if (items.isEmpty)
          EnvEmptyState(
            icon: OmniIcons.film,
            title: l10n.videoNoWatchHistory,
            message: l10n.videoRedesignNoHistoryHint,
          )
        else
          for (final item in items)
            MobileFeatureListRow(
              icon: OmniIcons.film,
              neutralIcon: true,
              title: item.title,
              detail: _detailOf(context, item),
              onTap:
                  item.videoItemId.isEmpty
                      ? null
                      : () => context.push(
                        movieDetailRouteFromIds(
                          videoItemId: item.videoItemId,
                          seriesId: item.seriesId,
                        ),
                      ),
              trailing:
                  onDelete == null
                      ? null
                      : MobileEnvInlineIconButton(
                        tooltip: l10n.coreDelete,
                        icon: Icons.close,
                        onTap: () => onDelete!(item),
                      ),
            ),
        if (isLoadingMore)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.env.inkMuted,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _detailOf(BuildContext context, MovieWatchHistory item) {
    final time = movieRedesignRelativeTime(context, item.playedAt);
    final progress = movieHistoryProgressLabel(item);
    final duration = movieHistoryDurationLabel(item);
    return [
      time,
      if (duration.isNotEmpty) duration,
      if (progress.isNotEmpty && progress != duration) progress,
    ].join(' · ');
  }
}
