import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
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
    super.key,
  });

  final List<MovieWatchHistory> items;
  final ValueChanged<MovieWatchHistory>? onDelete;
  final VoidCallback? onClearAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.movieRedesign;
    return Column(
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
                  title: item.title,
                  subtitle: _subtitleOf(context, item),
                  timeText: movieRedesignRelativeTime(context, item.playedAt),
                  progressText: _progressText(item),
                  thumbUrl: item.posterUrl,
                  onTap:
                      item.videoItemId.isEmpty
                          ? null
                          : () => context.push('/video/${item.videoItemId}'),
                  onDelete: onDelete == null ? null : () => onDelete!(item),
                ),
            ],
          ),
      ],
    );
  }

  String _subtitleOf(BuildContext context, MovieWatchHistory item) {
    final duration = movieRedesignFormatDuration(item.durationSeconds);
    if (duration.isEmpty) {
      return item.completed ? '100%' : '';
    }
    return duration;
  }

  String _progressText(MovieWatchHistory item) {
    if (item.completed) {
      return '100%';
    }
    return '${item.progressPercent.round()}%';
  }
}
