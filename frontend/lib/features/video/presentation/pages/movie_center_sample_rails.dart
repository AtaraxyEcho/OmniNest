part of 'movie_center_page.dart';

/// 样例海报卡副题（年份 · 时长 · ★评分）。
String _movieCardSubtitle(MovieVideoItem item) {
  final runtimeMinutes =
      item.runtimeSeconds == null ? null : item.runtimeSeconds! ~/ 60;
  final parts = <String>[
    item.year,
    if (runtimeMinutes != null && runtimeMinutes > 0) '$runtimeMinutes min',
    if (item.rating != null && item.rating! > 0)
      '★ ${item.rating!.toStringAsFixed(1)}',
  ];
  return parts.join(' · ');
}

/// film-row 尾部更多钮（样例 more 18px 弱化）：跳转详情页承载动作。
class _FilmMoreButton extends StatelessWidget {
  const _FilmMoreButton({required this.item});

  final MovieVideoItem item;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: AppLocalizations.of(context).videoMore,
      onPressed: () => context.push(movieDetailRoute(item)),
      icon: Icon(
        Icons.more_horiz_rounded,
        size: 18,
        color: context.env.inkFaint,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// cinema-hero 规格徽标（样例 cinema-badge）：按分辨率档位给 4K/1080P。
String? _movieBadgeText(MovieVideoItem? item) {
  final height = item?.resolutionHeight;
  if (height == null || height <= 0) {
    return null;
  }
  if (height >= 2000) {
    return '4K';
  }
  if (height >= 1000) {
    return '1080P';
  }
  return '${height}P';
}

/// 托管续播轨（样例 Continue poster-rail）。
Widget _hostedContinueRail(BuildContext context, MovieCenterState state) {
  if (state.continueWatching.isEmpty) {
    return const SizedBox.shrink();
  }
  return SampleRail(
    children: [
      for (final item in state.continueWatching)
        SamplePosterCard(
          imageUrl: item.posterUrl,
          title: item.title,
          subtitle: _episodeLabelOf(item) ?? '',
          progress:
              item.progressPercent > 0 ? item.progressPercent / 100 : null,
          onTap:
              () => unawaited(
                context.push(
                  movieDetailRouteFromIds(
                    videoItemId: item.id,
                    seriesId: item.seriesId,
                  ),
                ),
              ),
          onPlay: () => unawaited(context.push(moviePlayRoute(item.id))),
        ),
    ],
  );
}

/// 托管 Films 档行列表（样例 film-row）：42×58 海报 + 标题/副题 + 更多钮。
Widget _hostedFilmRows(List<MovieVideoItem> items) {
  return SliverPadding(
    padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
    sliver: SliverList.separated(
      itemBuilder: (context, index) {
        final item = items[index];
        return SampleFilmRow(
          imageUrl: item.posterUrl,
          title: item.title,
          subtitle: _movieCardSubtitle(item),
          onTap: () => context.push(movieDetailRoute(item)),
          trailing: _FilmMoreButton(item: item),
        );
      },
      separatorBuilder: (_, _) => const SizedBox.shrink(),
      itemCount: items.length,
    ),
  );
}
