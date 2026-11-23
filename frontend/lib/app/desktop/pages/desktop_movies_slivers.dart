part of 'desktop_movies_page.dart';

/// E-06：使用 `SliverLayoutBuilder` + `SliverGrid.builder` 恢复视口懒加载虚拟化。
class _PosterSliverGrid extends StatelessWidget {
  const _PosterSliverGrid({required this.items});

  final List<MovieVideoItem> items;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = _posterGridColumns(
          context,
          constraints.crossAxisExtent,
        );
        return SliverPadding(
          padding: const EdgeInsets.only(bottom: DesktopMetrics.sectionGap + 8),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 22,
              mainAxisSpacing: 22,
              childAspectRatio: 2 / 3,
            ),
            itemCount: items.length,
            itemBuilder:
                (context, index) => DesktopStagger(
                  index: index < 12 ? index : 0,
                  child: _PosterCard(item: items[index]),
                ),
          ),
        );
      },
    );
  }
}

class _SeriesSliverGrid extends StatelessWidget {
  const _SeriesSliverGrid({required this.items});

  final List<MovieSeries> items;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = _posterGridColumns(
          context,
          constraints.crossAxisExtent,
        );
        return SliverPadding(
          padding: const EdgeInsets.only(bottom: DesktopMetrics.sectionGap + 8),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 22,
              mainAxisSpacing: 22,
              childAspectRatio: 2 / 3,
            ),
            itemCount: items.length,
            itemBuilder:
                (context, index) => DesktopStagger(
                  index: index < 12 ? index : 0,
                  child: _SeriesPoster(series: items[index]),
                ),
          ),
        );
      },
    );
  }
}
