import 'package:cached_network_image/cached_network_image.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:flutter/material.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';

/// 相册卡片
class PhotoAlbumCard extends StatelessWidget {
  const PhotoAlbumCard({
    required this.album,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final PhotoAlbum album;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            color: context.photosColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: context.photosColors.outlineVariant.withValues(
                alpha: 0.24,
              ),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面区域
              Expanded(
                child: Container(
                  color: context.photosColors.surfaceContainerHighest,
                  child:
                      album.hasCover
                          ? CachedNetworkImage(
                            imageUrl: album.coverUrl!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            memCacheWidth: 300,
                            placeholder:
                                (context, url) => Center(
                                  child: Icon(
                                    Icons.photo_album_outlined,
                                    color: context.photosColors.onSurfaceVariant
                                        .withValues(alpha: 0.3),
                                    size: 32,
                                  ),
                                ),
                            errorWidget:
                                (context, url, error) => Center(
                                  child: Icon(
                                    Icons.photo_album_outlined,
                                    color: context.photosColors.onSurfaceVariant
                                        .withValues(alpha: 0.3),
                                    size: 32,
                                  ),
                                ),
                          )
                          : Center(
                            child: Icon(
                              Icons.photo_album_outlined,
                              color: context.photosColors.onSurfaceVariant
                                  .withValues(alpha: 0.3),
                              size: 32,
                            ),
                          ),
                ),
              ),
              // 信息区域
              Padding(
                padding: EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.photosColors.onSurface,
                        fontSize: AppTypography.bodyLarge,
                        height: 18 / 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      AppLocalizations.of(
                        context,
                      ).photosAlbumPhotoCountLabel(album.photoCount),
                      style: TextStyle(
                        color: context.photosColors.onSurfaceVariant,
                        fontSize: AppTypography.bodySmall,
                        height: 16 / 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
