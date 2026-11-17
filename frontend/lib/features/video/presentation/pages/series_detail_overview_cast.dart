part of 'series_detail_page.dart';

/// 简介与 CAST 区块。
class _SeriesOverviewText extends StatelessWidget {
  const _SeriesOverviewText({
    required this.overview,
    required this.editMode,
    required this.overviewController,
  });

  final String overview;
  final bool editMode;
  final TextEditingController overviewController;

  @override
  Widget build(BuildContext context) {
    if (editMode) {
      return TextField(
        controller: overviewController,
        minLines: 2,
        maxLines: 5,
        cursorColor: MovieDetailTheme.accent,
        style: MovieDetailTheme.body(
          14,
          color: MovieDetailTheme.secondaryText,
          height: 1.6,
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: MovieDetailTheme.surface,
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: MovieDetailTheme.accent.withValues(alpha: 0.30),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: MovieDetailTheme.accent.withValues(alpha: 0.30),
            ),
          ),
          contentPadding: const EdgeInsets.all(12),
        ),
      );
    }
    if (overview.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 672),
      child: Text(
        overview,
        style: MovieDetailTheme.body(
          14,
          color: MovieDetailTheme.secondaryText,
          height: 1.6,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: MovieDetailTheme.mono(AppTypography.bodySmall, letterSpacing: 2),
    );
  }
}

class _SeriesCastHeader extends StatelessWidget {
  const _SeriesCastHeader();

  @override
  Widget build(BuildContext context) {
    return const _SectionHeader(label: 'CAST');
  }
}

class _SeriesCastGrid extends StatelessWidget {
  const _SeriesCastGrid({required this.cast});

  final List<MovieCastMember> cast;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 800 ? 3 : 2;
        const gap = 12.0;
        final itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final member in cast.take(12))
              SizedBox(
                width: itemWidth,
                child: Row(
                  children: [
                    _CastAvatar(
                      name: member.name,
                      profileUrl: member.profilePath,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MovieDetailTheme.body(
                              14,
                              color: MovieDetailTheme.foreground,
                            ),
                          ),
                          if (member.character != null &&
                              member.character!.isNotEmpty)
                            Text(
                              member.character!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MovieDetailTheme.mono(
                                AppTypography.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CastAvatar extends StatelessWidget {
  const _CastAvatar({required this.name, this.profileUrl});

  final String name;
  final String? profileUrl;

  @override
  Widget build(BuildContext context) {
    final url = profileUrl;
    return Container(
      width: 48,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: MovieDetailTheme.surface,
      ),
      child:
          url != null && url.isNotEmpty
              ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: 96,
                errorWidget:
                    (context, error, stackTrace) => _CastInitials(name: name),
              )
              : _CastInitials(name: name),
    );
  }
}

class _CastInitials extends StatelessWidget {
  const _CastInitials({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    return Center(
      child: Text(
        initial,
        style: MovieDetailTheme.mono(
          AppTypography.titleMedium,
          color: MovieDetailTheme.accent,
        ),
      ),
    );
  }
}
