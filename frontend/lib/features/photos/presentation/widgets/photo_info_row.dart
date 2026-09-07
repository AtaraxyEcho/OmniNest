import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/photos/domain/photo.dart';

/// 照片信息行：左标签右数值、底部分隔线（设计稿 Photo Info 行样式）。
///
/// 幻灯片 Info 面板与详情页信息侧栏共用；深色面板使用默认配色，
/// 亮色主题下由调用方传入主题化颜色。
class PhotoInfoRow extends StatelessWidget {
  const PhotoInfoRow({
    required this.label,
    required this.value,
    this.labelColor = const Color(0x59FFFFFF),
    this.valueColor = const Color(0xC0FFFFFF),
    this.dividerColor = const Color(0x14FFFFFF),
    super.key,
  });

  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;
  final Color dividerColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 11,
              letterSpacing: 0.04,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor,
                fontSize: 12,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 照片信息条目数据。
class PhotoInfoEntry {
  const PhotoInfoEntry(this.label, this.value);

  final String label;
  final String value;
}

/// 信息侧栏底部操作按钮：半透明白底圆角块，Like/Share 共用样式。
///
/// 幻灯片 Info 面板与详情页信息侧栏使用同一规格；[iconColor] 用于
/// 收藏态的玫红心形等强调色。
class PhotoPanelActionButton extends StatelessWidget {
  const PhotoPanelActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: iconColor ?? Colors.white.withValues(alpha: 0.80),
              ),
              const SizedBox(width: 8),
              // 长文案（如英文 Unfavorite）超宽时省略，避免信息面板按钮溢出。
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.80),
                    fontSize: 12,
                    letterSpacing: 0.04,
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

/// 幻灯片 Info 与详情页信息侧栏（共享 PhotoInfoPanel）的统一字段集，
/// 有值才渲染、顺序一致。新增字段只改此处，两个宿主自动同步。
List<PhotoInfoEntry> buildPhotoInfoEntries(
  PhotoItem photo,
  AppLocalizations l10n, {
  required bool preferZh,
}) {
  final entries = <PhotoInfoEntry>[];
  void add(String label, String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    entries.add(PhotoInfoEntry(label, trimmed));
  }

  add(
    l10n.photosFormat,
    photo.format.isNotEmpty ? photo.format.toUpperCase() : null,
  );
  add(l10n.photosFileSize, photo.fileSizeDisplay);
  add(l10n.photosResolution, photo.resolutionDisplay);
  if (photo.dateTaken != null) {
    final d = photo.dateTaken!;
    add(
      l10n.photosDateTaken,
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
    );
  }
  add(l10n.photosBrand, photo.cameraMake);
  add(l10n.photosModel, photo.cameraModel);
  add(l10n.photosLens, photo.lensModel);
  if (photo.aperture != null) {
    add(l10n.photosAperture, 'f/${photo.aperture}');
  }
  add(l10n.photosShutterSpeed, photo.shutterSpeed);
  if (photo.iso != null) {
    add('ISO', '${photo.iso}');
  }
  if (photo.focalLength != null) {
    add(l10n.photosFocalLength, '${photo.focalLength}mm');
  }
  add(l10n.photosFlash, photo.flash);
  add(l10n.photosWhiteBalance, photo.whiteBalance);
  add(l10n.photosMeteringMode, photo.meteringMode);
  add(l10n.photosPlace, photo.locationDisplay(preferZh: preferZh));
  if (photo.gpsLatitude != null && photo.gpsLongitude != null) {
    add(
      l10n.photosCoordinates,
      '${photo.gpsLatitude!.toStringAsFixed(6)}, ${photo.gpsLongitude!.toStringAsFixed(6)}',
    );
  }
  return entries;
}
