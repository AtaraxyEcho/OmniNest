import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_common_widgets.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_info_row.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';

/// EXIF 信息侧栏：设计稿 w-72 独立全高侧栏，堆叠式标签/数值行。
class PhotoExifPanel extends ConsumerWidget {
  const PhotoExifPanel({super.key, required this.photo});

  final PhotoItem photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark
            ? FramePalette.viewerPanel
            : context.photosColors.surfaceContainer;
    final headerColor =
        isDark
            ? Colors.white.withValues(alpha: 0.90)
            : context.photosColors.onSurface;
    final sectionColor =
        isDark
            ? Colors.white.withValues(alpha: 0.50)
            : context.photosColors.onSurfaceVariant;
    final labelColor =
        isDark
            ? Colors.white.withValues(alpha: 0.35)
            : context.photosColors.onSurfaceVariant.withValues(alpha: 0.7);
    final valueColor =
        isDark
            ? Colors.white.withValues(alpha: 0.80)
            : context.photosColors.onSurface;
    final dividerColor =
        isDark
            ? Colors.white.withValues(alpha: 0.08)
            : context.photosColors.outlineVariant.withValues(alpha: 0.24);
    final pillBackground =
        isDark
            ? Colors.white.withValues(alpha: 0.10)
            : context.photosColors.surfaceContainerHighest;
    final pillColor =
        isDark
            ? Colors.white.withValues(alpha: 0.60)
            : context.photosColors.onSurfaceVariant;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(left: BorderSide(color: dividerColor)),
      ),
      child: SingleChildScrollView(
        // 顶部留白避开浮层顶栏（设计稿 pt-16）。
        padding: const EdgeInsets.fromLTRB(20, 68, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).photosPhotoInfo,
              style: TextStyle(
                color: headerColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 20),
            _ExifSection(
              title: AppLocalizations.of(context).photosBasicInfo,
              sectionColor: sectionColor,
              children: [
                if (photo.format.isNotEmpty)
                  _ExifEntry(
                    label: AppLocalizations.of(context).photosFormat,
                    value: photo.format.toUpperCase(),
                    labelColor: labelColor,
                    valueColor: valueColor,
                  ),
                _ExifEntry(
                  label: AppLocalizations.of(context).photosFileSize,
                  value: photo.fileSizeDisplay,
                  labelColor: labelColor,
                  valueColor: valueColor,
                ),
                if (photo.resolutionDisplay != null)
                  _ExifEntry(
                    label: AppLocalizations.of(context).photosResolution,
                    value: photo.resolutionDisplay!,
                    labelColor: labelColor,
                    valueColor: valueColor,
                  ),
                if (photo.dateTaken != null)
                  _ExifEntry(
                    label: AppLocalizations.of(context).photosDateTaken,
                    value: _formatDate(photo.dateTaken!),
                    labelColor: labelColor,
                    valueColor: valueColor,
                  ),
              ],
            ),
            if (photo.hasExif) ...[
              const SizedBox(height: 20),
              _ExifSection(
                title: AppLocalizations.of(context).photosCameraInfo,
                sectionColor: sectionColor,
                children: [
                  if (photo.cameraMake != null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosBrand,
                      value: photo.cameraMake!,
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                  if (photo.cameraModel != null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosModel,
                      value: photo.cameraModel!,
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                  if (photo.lensModel != null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosLens,
                      value: photo.lensModel!,
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                  if (photo.aperture != null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosAperture,
                      value: 'f/${photo.aperture}',
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                  if (photo.shutterSpeed != null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosShutterSpeed,
                      value: photo.shutterSpeed!,
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                  if (photo.iso != null)
                    _ExifEntry(
                      label: 'ISO',
                      value: '${photo.iso}',
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                  if (photo.focalLength != null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosFocalLength,
                      value: '${photo.focalLength}mm',
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                ],
              ),
            ],
            if (photo.hasAdvancedExif) ...[
              const SizedBox(height: 20),
              _ExifSection(
                title: AppLocalizations.of(context).photosShootingParams,
                sectionColor: sectionColor,
                children: [
                  if (photo.flash != null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosFlash,
                      value: photo.flash!,
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                  if (photo.whiteBalance != null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosWhiteBalance,
                      value: photo.whiteBalance!,
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                  if (photo.meteringMode != null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosMeteringMode,
                      value: photo.meteringMode!,
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                ],
              ),
            ],
            if (photo.hasGps) ...[
              const SizedBox(height: 20),
              _ExifSection(
                title: AppLocalizations.of(context).photosLocationInfo,
                sectionColor: sectionColor,
                children: [
                  if (photo.locationDisplay(preferZh: _isZhLocale(context)) !=
                      null)
                    _ExifEntry(
                      label: AppLocalizations.of(context).photosPlace,
                      value:
                          photo.locationDisplay(
                            preferZh: _isZhLocale(context),
                          )!,
                      labelColor: labelColor,
                      valueColor: valueColor,
                    ),
                  _ExifEntry(
                    label: AppLocalizations.of(context).photosCoordinates,
                    value:
                        '${photo.gpsLatitude!.toStringAsFixed(6)}, ${photo.gpsLongitude!.toStringAsFixed(6)}',
                    labelColor: labelColor,
                    valueColor: valueColor,
                  ),
                ],
              ),
            ],
            if (photo.contentAnalysis?.labels.isNotEmpty == true) ...[
              const SizedBox(height: 20),
              Text(
                AppLocalizations.of(context).photosAIRecognition,
                style: TextStyle(
                  color: sectionColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              for (final entry
                  in photo.contentAnalysis!.labelsByNamespace.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    _localizedPhotoAnalysisNamespace(context, entry.key),
                    style: TextStyle(
                      color: labelColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final label in entry.value)
                      _InfoPill(
                        text: _localizedPhotoContentLabel(context, label.code),
                        background: pillBackground,
                        foreground: pillColor,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ],
            if (photo.description != null && photo.description!.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                AppLocalizations.of(context).photosDescription,
                style: TextStyle(
                  color: sectionColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                photo.description!,
                style: TextStyle(
                  color: valueColor,
                  fontSize: 13,
                  height: 18 / 13,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context).photosTag,
              style: TextStyle(
                color: sectionColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in photo.tags)
                  _InfoPill(
                    text: _localizedPhotoAiCategory(context, tag),
                    background: pillBackground,
                    foreground: pillColor,
                    onRemoved: () async {
                      try {
                        await ref
                            .read(photoCenterControllerProvider.notifier)
                            .removeTag(photo.id, tag);
                        if (!context.mounted) return;
                        ref.invalidate(photoDetailProvider(photo.id));
                      } on Exception {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppLocalizations.of(
                                  context,
                                ).photosDeleteTagFailed,
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                _InfoPill(
                  text: AppLocalizations.of(context).photosAddTag,
                  background: context.frameColors.accent.withValues(
                    alpha: 0.12,
                  ),
                  foreground: context.frameColors.accent,
                  icon: Icons.add,
                  onRemoved: () => _showAddTagDialog(context, ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddTagDialog(BuildContext context, WidgetRef ref) async {
    final tag = await showDialog<String>(
      context: context,
      builder:
          (ctx) => PhotoDialogTextField(
            builder:
                (ctx, controller) => AlertDialog(
                  backgroundColor: context.photosColors.surfaceContainerHigh,
                  title: Text(
                    AppLocalizations.of(context).photosAddTag,
                    style: TextStyle(color: context.photosColors.onSurface),
                  ),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    style: TextStyle(color: context.photosColors.onSurface),
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context).photosTagNameInput,
                      hintStyle: TextStyle(
                        color: context.photosColors.onSurfaceVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: context.photosColors.outlineVariant.withValues(
                            alpha: 0.32,
                          ),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: context.photosColors.primaryContainer,
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(AppLocalizations.of(context).photosCancel),
                    ),
                    FilledButton(
                      onPressed:
                          () => Navigator.pop(ctx, controller.text.trim()),
                      child: Text(AppLocalizations.of(context).photosAdd),
                    ),
                  ],
                ),
          ),
    );
    if (tag != null && tag.isNotEmpty && context.mounted) {
      try {
        await ref
            .read(photoCenterControllerProvider.notifier)
            .addTag(photo.id, tag);
        if (!context.mounted) return;
        ref.invalidate(photoDetailProvider(photo.id));
      } on Exception {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).photosAddTagFailed),
            ),
          );
        }
      }
    }
  }
}

/// EXIF 分组标题。
class _ExifSection extends StatelessWidget {
  const _ExifSection({
    required this.title,
    required this.sectionColor,
    required this.children,
  });

  final String title;
  final Color sectionColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: sectionColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }
}

/// 设计稿 EXIF 行：标签在上、数值在下，行间 14px。
class _ExifEntry extends StatelessWidget {
  const _ExifEntry({
    required this.label,
    required this.value,
    required this.labelColor,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    // 行样式与幻灯片 Info 统一（左右分布 + 底部分隔线），分隔色随主题。
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor =
        isDark
            ? const Color(0x14FFFFFF)
            : Theme.of(context).dividerColor.withValues(alpha: 0.24);
    return PhotoInfoRow(
      label: label,
      value: value,
      labelColor: labelColor,
      valueColor: valueColor,
      dividerColor: dividerColor,
    );
  }
}

/// 设计稿标签胶囊：全圆角、半透明底、可带关闭或加号动作。
class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.text,
    required this.background,
    required this.foreground,
    this.icon,
    this.onRemoved,
  });

  final String text;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final VoidCallback? onRemoved;

  @override
  Widget build(BuildContext context) {
    final action = onRemoved;
    return Material(
      color: background,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: foreground),
                const SizedBox(width: 4),
              ],
              Text(text, style: TextStyle(color: foreground, fontSize: 12)),
              if (action != null && icon == null) ...[
                const SizedBox(width: 4),
                Icon(Icons.close_rounded, size: 14, color: foreground),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

/// 当前界面语言是否为中文，用于地名等双语数据的选择。
bool _isZhLocale(BuildContext context) {
  return Localizations.localeOf(context).languageCode == 'zh';
}

String _localizedPhotoAiCategory(BuildContext context, String category) {
  final l10n = AppLocalizations.of(context);
  return switch (category) {
    'Person' => l10n.photosAiCategoryPerson,
    'Cat' => l10n.photosAiCategoryCat,
    'Dog' => l10n.photosAiCategoryDog,
    'Animal' => l10n.photosAiCategoryAnimal,
    'Nature' || 'Landscape' => l10n.photosAiCategoryNature,
    'Architecture' => l10n.photosAiCategoryArchitecture,
    'Indoor' => l10n.photosAiCategoryIndoor,
    'Food' => l10n.photosAiCategoryFood,
    'Vehicle' => l10n.photosAiCategoryVehicle,
    'Plant' => l10n.photosAiCategoryPlant,
    'Sport' => l10n.photosAiCategorySport,
    'Night' => l10n.photosAiCategoryNight,
    'Art' => l10n.photosAiCategoryArt,
    'Document' => l10n.photosAiCategoryDocument,
    _ => category,
  };
}

String _localizedPhotoContentLabel(BuildContext context, String code) {
  return _localizedPhotoAiCategory(context, switch (code) {
    'person' => 'Person',
    'cat' => 'Cat',
    'dog' => 'Dog',
    'bird' => 'Animal',
    'horse' ||
    'sheep' ||
    'cow' ||
    'elephant' ||
    'bear' ||
    'zebra' ||
    'giraffe' => 'Animal',
    'nature' ||
    'beach' ||
    'mountain' ||
    'forest' ||
    'lake' ||
    'ocean' ||
    'river' => 'Nature',
    'indoor' ||
    'office' ||
    'restaurant' ||
    'kitchen' ||
    'bedroom' ||
    'classroom' => 'Indoor',
    'vehicle' => 'Vehicle',
    'food' => 'Food',
    'plant' => 'Plant',
    'document' || 'screenshot' => 'Document',
    'illustration' || 'anime' || 'artwork' => 'Art',
    _ => code,
  });
}

String _localizedPhotoAnalysisNamespace(
  BuildContext context,
  String namespace,
) {
  final l10n = AppLocalizations.of(context);
  return switch (namespace) {
    'SUBJECT' => l10n.photosAnalysisSubject,
    'SCENE' => l10n.photosAnalysisScene,
    'STYLE' => l10n.photosAnalysisStyle,
    _ => l10n.photosAIRecognition,
  };
}
