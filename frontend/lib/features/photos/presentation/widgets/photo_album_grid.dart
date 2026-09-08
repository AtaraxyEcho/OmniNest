import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_album_card.dart';

/// 相册管理网格：相册卡片 + 新建入口，供图库货架的"管理"页与嵌入场景复用。
class PhotoAlbumGrid extends StatelessWidget {
  const PhotoAlbumGrid({
    required this.albums,
    required this.onOpenAlbum,
    required this.onDeleteAlbum,
    required this.onCreateAlbum,
    super.key,
  });

  final List<PhotoAlbum> albums;
  final ValueChanged<PhotoAlbum> onOpenAlbum;
  final ValueChanged<PhotoAlbum> onDeleteAlbum;
  final VoidCallback onCreateAlbum;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 1200
                ? 5
                : constraints.maxWidth >= 900
                ? 4
                : constraints.maxWidth >= 600
                ? 3
                : 2;
        final itemCount = albums.length + 1; // +1 for create button
        return GridView.builder(
          itemCount: itemCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemBuilder: (context, index) {
            if (index == albums.length) {
              return CreateAlbumTile(onTap: onCreateAlbum);
            }
            final album = albums[index];
            return PhotoAlbumCard(
              album: album,
              onTap: () => onOpenAlbum(album),
              onLongPress: () => onDeleteAlbum(album),
            );
          },
        );
      },
    );
  }
}

class CreateAlbumTile extends StatelessWidget {
  const CreateAlbumTile({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: context.photosColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: context.photosColors.outlineVariant.withValues(
                alpha: 0.24,
              ),
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: context.photosColors.primaryContainer.withValues(
                    alpha: 0.14,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: context.photosColors.primaryContainer,
                  size: 24,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                AppLocalizations.of(context).photosNewAlbum,
                style: TextStyle(
                  color: context.photosColors.primaryContainer,
                  fontSize: AppTypography.bodyMedium,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
