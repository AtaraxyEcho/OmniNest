part of 'desktop_photos_page.dart';

class _JustifiedPhotos extends StatefulWidget {
  const _JustifiedPhotos({
    required this.photos,
    required this.targetHeight,
    required this.selection,
    required this.onActivate,
    required this.onToggleSelect,
    this.onSecondaryTap,
    this.onInspect,
    this.selectionMode = false,
    this.orderContext,
    this.onOrderChanged,
    this.showCaption = true,
    this.showFavorite = true,
    this.showSelectionControls = true,
  });

  final List<PhotoItem> photos;
  final double targetHeight;
  final Set<String> selection;
  final void Function(PhotoItem photo, List<PhotoItem> photos) onActivate;
  final ValueChanged<PhotoItem> onToggleSelect;
  final void Function(
    PhotoItem photo,
    List<PhotoItem> photos,
    Offset globalPosition,
  )?
  onSecondaryTap;
  final void Function(PhotoItem photo, List<PhotoItem> photos)? onInspect;
  final bool selectionMode;
  final String? orderContext;
  final _PhotoOrderChanged? onOrderChanged;
  final bool showCaption;
  final bool showFavorite;
  final bool showSelectionControls;

  @override
  State<_JustifiedPhotos> createState() => _JustifiedPhotosState();
}
