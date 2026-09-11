import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_media_thumbnail.dart';
import 'package:omninest/features/photos/domain/photo.dart';

class RecentPhotosWidget extends StatelessWidget {
  const RecentPhotosWidget({required this.photos, super.key});
  final List<PhotoItem> photos;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/photos'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.photo_outlined,
                    color: colorScheme.tertiary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.portalRecentPhotos,
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (photos.isEmpty)
                Text(
                  l10n.portalNoPhotos,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else ...[
                Row(
                  children:
                      photos
                          .take(3)
                          .map(
                            (p) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: PortalMediaThumbnail(
                                    imageUrl: p.coverUrl,
                                    // 单维约束解码：方形双维会把源图拉伸
                                    // 压扁，宽度约束后由 cover 居中裁切。
                                    cacheWidth: 320,
                                    borderRadius: BorderRadius.circular(6),
                                    fallback: Container(
                                      color:
                                          theme
                                              .colorScheme
                                              .surfaceContainerHighest,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.portalNewPhotoCount(photos.length),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
