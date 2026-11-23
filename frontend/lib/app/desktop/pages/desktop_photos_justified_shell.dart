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

/// 按行 Sliver 虚拟化的 Justified 照片流，供 [SliverMainAxisGroup] 按日分组消费。
class _SliverJustifiedPhotos extends StatefulWidget {
  const _SliverJustifiedPhotos({
    super.key,
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
    this.onRowHoverEnter,
    this.onRowHoverExit,
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

  /// 日分组与 Justified 流共用同一套磁贴开关，当前仅此一处消费，故不再从构造参数透传。
  final bool showCaption = true;
  final bool showFavorite = true;
  final bool showSelectionControls = true;
  final VoidCallback? onRowHoverEnter;
  final VoidCallback? onRowHoverExit;

  @override
  State<_SliverJustifiedPhotos> createState() => _SliverJustifiedPhotosState();
}

class _SliverJustifiedPhotosState extends State<_SliverJustifiedPhotos>
    with
        TickerProviderStateMixin,
        _JustifiedPhotosStateMixin<_SliverJustifiedPhotos> {
  @override
  List<PhotoItem> get _photos => widget.photos;
  @override
  double get _targetHeight => widget.targetHeight;
  @override
  Set<String> get _selection => widget.selection;
  @override
  void Function(PhotoItem photo, List<PhotoItem> photos) get _onActivate =>
      widget.onActivate;
  @override
  ValueChanged<PhotoItem> get _onToggleSelect => widget.onToggleSelect;
  @override
  void Function(PhotoItem photo, List<PhotoItem> photos, Offset globalPosition)?
  get _onSecondaryTap => widget.onSecondaryTap;
  @override
  void Function(PhotoItem photo, List<PhotoItem> photos)? get _onInspect =>
      widget.onInspect;
  @override
  bool get _selectionMode => widget.selectionMode;
  @override
  String? get _orderContext => widget.orderContext;
  @override
  _PhotoOrderChanged? get _onOrderChanged => widget.onOrderChanged;
  @override
  bool get _showCaption => widget.showCaption;
  @override
  bool get _showFavorite => widget.showFavorite;
  @override
  bool get _showSelectionControls => widget.showSelectionControls;
  @override
  VoidCallback? get _onRowHoverEnter => widget.onRowHoverEnter;
  @override
  VoidCallback? get _onRowHoverExit => widget.onRowHoverExit;

  @override
  Widget build(BuildContext context) => _buildSliverJustified(context);
}
