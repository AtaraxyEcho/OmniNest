part of 'desktop_photo_viewer_page.dart';

/// 右侧信息面板：独立成 part，避免查看器主文件继续膨胀。
class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.open,
    required this.photo,
    required this.scale,
    required this.onClose,
    required this.onZoom,
  });

  final bool open;
  final PhotoItem photo;
  final double scale;
  final VoidCallback onClose;
  final ValueChanged<double> onZoom;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final exposure = [
      if (photo.aperture != null) photo.aperture!,
      if (photo.shutterSpeed != null) photo.shutterSpeed!,
      if (photo.iso != null) 'ISO ${photo.iso}',
      if (photo.focalLength != null) photo.focalLength!,
    ].join(' · ');
    final camera = [
      photo.cameraMake,
      photo.cameraModel,
    ].whereType<String>().where((part) => part.isNotEmpty).join(' ');
    final dimensions =
        photo.width != null && photo.height != null
            ? '${photo.width} × ${photo.height}'
            : '—';
    // 样例 `.vw-info`：浮在舞台上的圆角卡，顶栏之下（top 76）、胶片条之上
    // （bottom 96），宽 330，不挤压画面。
    return AnimatedPositioned(
      duration: DesktopMotion.of(context, DesktopMotion.pane),
      curve: DesktopMotion.ease,
      top: 76,
      bottom: 96,
      right: open ? 16 : -346,
      child: IgnorePointer(
        ignoring: !open,
        child: Container(
          width: 330,
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
          decoration: BoxDecoration(
            color: skin.pop,
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusLarge),
            border: Border.all(color: skin.line2),
            boxShadow: skin.shadow,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.desktopPhotosInfo.toUpperCase(),
                        style: DesktopType.eyebrow(skin.text3),
                      ),
                    ),
                    DesktopIconButton(
                      icon: DesktopIcons.close,
                      size: 28,
                      iconSize: 14,
                      onPressed: onClose,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(photo.title, style: DesktopType.displaySm(skin.text)),
                const SizedBox(height: 16),
                DesktopKeyValues(
                  entries: [
                    if (photo.dateTaken != null)
                      MapEntry(
                        l10n.desktopPhotosTaken,
                        _formatDateTime(photo.dateTaken!),
                      ),
                    if (_placeLabel(photo) != null)
                      MapEntry(l10n.desktopPhotosLocation, _placeLabel(photo)!),
                    if (camera.isNotEmpty)
                      MapEntry(l10n.desktopPhotosCamera, camera),
                    if (exposure.isNotEmpty)
                      MapEntry(l10n.desktopPhotosExposure, exposure),
                    MapEntry(
                      l10n.desktopPhotosDimensions,
                      '$dimensions · ${formatFileSize(photo.fileSize)}',
                    ),
                  ],
                ),
                if (photo.tags.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    l10n.desktopPhotosTags.toUpperCase(),
                    style: DesktopType.eyebrow(skin.text3),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final tag in photo.tags) DesktopChip(tag)],
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  l10n.desktopPhotosZoom.toUpperCase(),
                  style: DesktopType.eyebrow(skin.text3),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    DesktopIconButton(
                      icon: DesktopIcons.zoomOut,
                      size: 28,
                      iconSize: 14,
                      onPressed: () => onZoom(scale - 0.5),
                    ),
                    Expanded(
                      child: DesktopSlider(
                        value: scale.clamp(1, 5),
                        max: 5,
                        onChanged: onZoom,
                      ),
                    ),
                    DesktopIconButton(
                      icon: DesktopIcons.zoomIn,
                      size: 28,
                      iconSize: 14,
                      onPressed: () => onZoom(scale + 0.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `gpsLocation` 是后端原样下发的地址字段集合，取第一个可读值。
String? _placeLabel(PhotoItem photo) {
  final location = photo.gpsLocation;
  if (location == null || location.isEmpty) return null;
  for (final key in const ['name', 'displayName', 'locality', 'city']) {
    final value = location[key];
    if (value is String && value.isNotEmpty) return value;
  }
  return null;
}

String _formatDateTime(DateTime value) {
  final l = value.toLocal();
  String p(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${p(l.month)}-${p(l.day)} ${p(l.hour)}:${p(l.minute)}';
}
