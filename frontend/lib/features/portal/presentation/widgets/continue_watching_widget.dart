import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_media_thumbnail.dart';
import 'package:omninest/features/video/domain/movie_models.dart';

class ContinueWatchingWidget extends StatelessWidget {
  const ContinueWatchingWidget({required this.items, super.key});
  final List<MovieContinueWatching> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/video'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.movie_outlined,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.portalContinueWatching,
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                Text(
                  l10n.portalNoWatchingContent,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                ...items
                    .take(3)
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            PortalMediaThumbnail(
                              imageUrl: item.posterUrl,
                              cacheKey: 'portal-preview:video:${item.id}',
                              width: 40,
                              height: 56,
                              // 单维约束解码：高度主导槽位仅约束高度，
                              // 海报真实纵横比由 cover 裁切保持。
                              cacheHeight: 168,
                              borderRadius: BorderRadius.circular(4),
                              fallback: Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: item.progressPercent / 100,
                                      minHeight: 3,
                                      backgroundColor:
                                          theme
                                              .colorScheme
                                              .surfaceContainerHighest,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${item.progressPercent.round()}%',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
