part of 'desktop_photos_page.dart';

class _SizedPhoto {
  const _SizedPhoto({required this.photo, required this.ratio});

  final PhotoItem photo;
  final double ratio;
}

/// 样例 `.solo-note`：单张照片旁的拍摄信息块。
class _SoloNote extends StatelessWidget {
  const _SoloNote({required this.photo});

  final PhotoItem photo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final camera = <String?>[
      photo.cameraMake,
      photo.cameraModel,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' ');
    final exposure = <String?>[
      photo.aperture,
      photo.shutterSpeed,
      photo.iso == null ? null : 'ISO ${photo.iso}',
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.desktopPhotosSingleCapture.toUpperCase(),
          style: DesktopType.eyebrow(skin.text3),
        ),
        const SizedBox(height: 4),
        Text(
          photo.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: DesktopType.panelTitle(skin.text),
        ),
        if (_placeLabel(photo) case final place?) ...[
          const SizedBox(height: 2),
          Text(place, style: DesktopType.dense(skin.text3)),
        ],
        if (camera.isNotEmpty || exposure.isNotEmpty) ...[
          const SizedBox(height: 12),
          if (camera.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 74,
                    child: Text(
                      l10n.desktopPhotosCamera,
                      style: DesktopType.secondary(skin.text3),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      camera,
                      style: DesktopType.secondary(skin.text2),
                    ),
                  ),
                ],
              ),
            ),
          if (exposure.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 74,
                  child: Text(
                    l10n.desktopPhotosExposure,
                    style: DesktopType.secondary(skin.text3),
                  ),
                ),
                Expanded(
                  child: Text(
                    exposure,
                    style: DesktopType.secondary(skin.text2),
                  ),
                ),
              ],
            ),
        ],
      ],
    );
  }
}

/// 样例照片的 `place`：`gpsLocation` 里第一个可读地名。
String? _placeLabel(PhotoItem photo) {
  final location = photo.gpsLocation;
  if (location == null || location.isEmpty) {
    return null;
  }
  for (final key in const ['name', 'displayName', 'locality', 'city']) {
    final value = location[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}
