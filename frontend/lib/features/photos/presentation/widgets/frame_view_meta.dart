import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/photos/application/photo_center_models.dart';

/// Frame 视图对应的导航文案。
String frameViewLabel(AppLocalizations l10n, FrameView view) {
  return switch (view) {
    FrameView.grid => l10n.photosFrameNavPhotos,
    FrameView.timeline => l10n.photosViewTimeline,
    FrameView.locations => l10n.photosFrameNavLocations,
    FrameView.tags => l10n.photosFrameNavTags,
    FrameView.albums => l10n.photosAlbums,
    FrameView.favorites => l10n.photosTabFavorites,
    FrameView.trash => l10n.photosFrameNavTrash,
  };
}

/// Frame 视图导航图标，与设计稿线形图标对齐。
IconData frameViewIcon(FrameView view) {
  return switch (view) {
    FrameView.grid => Icons.image_outlined,
    FrameView.timeline => Icons.calendar_today_outlined,
    FrameView.locations => Icons.place_outlined,
    FrameView.tags => Icons.sell_outlined,
    FrameView.albums => Icons.folder_outlined,
    FrameView.favorites => Icons.favorite_border,
    FrameView.trash => Icons.delete_outlined,
  };
}
