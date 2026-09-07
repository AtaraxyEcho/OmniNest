import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_common_widgets.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_info_row.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';

/// EXIF 信息侧栏：与幻灯片 Info 面板统一的恒暗设计（w-72 全高侧栏）。
///
/// 视觉规格与幻灯片一致：0A0A0A 面板底、眉题 + 标题头部、
/// `buildPhotoInfoEntries` 平铺字段行；详情页独有的 AI 识别 / 描述 /
/// 标签交互保留在字段区下方，使用同一暗色语言。
class PhotoExifPanel extends ConsumerWidget {
  const PhotoExifPanel({super.key, required this.photo, required this.onShare});

  final PhotoItem photo;

  /// 底部 Share 按钮：由宿主关闭信息面板并打开分享侧栏。
  final VoidCallback onShare;

  static const Color _panelColor = Color(0xF00A0A0A);
  static const Color _borderColor = Color(0x12FFFFFF);
  static const Color _pillBackground = Color(0x12FFFFFF);
  static const Color _pillForeground = Color(0x99FFFFFF);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final preferZh = Localizations.localeOf(context).languageCode == 'zh';
    final rows = buildPhotoInfoEntries(photo, l10n, preferZh: preferZh);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: _panelColor,
        border: Border(left: BorderSide(color: _borderColor)),
      ),
      child: SingleChildScrollView(
        // 顶部留白避开浮层顶栏（设计稿 pt-16）。
        padding: const EdgeInsets.fromLTRB(24, 68, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).photosPhotoInfo,
              style: _eyebrowStyle,
            ),
            const SizedBox(height: 4),
            Text(
              photo.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 32),
            if (rows.isEmpty)
              Text(
                '—',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 12,
                ),
              )
            else
              for (final row in rows)
                PhotoInfoRow(label: row.label, value: row.value),
            ..._buildAiSection(context),
            ..._buildDescriptionSection(context),
            _buildTagSection(context, ref),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: PhotoPanelActionButton(
                    icon:
                        photo.favorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                    iconColor:
                        photo.favorite
                            ? const Color(0xFFFB7185)
                            : Colors.white.withValues(alpha: 0.80),
                    label:
                        photo.favorite
                            ? AppLocalizations.of(context).photosUnfavorite
                            : AppLocalizations.of(context).photosFavorite,
                    onTap: () => _toggleFavorite(context, ref),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PhotoPanelActionButton(
                    icon: Icons.share_rounded,
                    label: l10n.photosSharePhoto,
                    onTap: onShare,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 眉题/分区标题样式，与幻灯片 Info 面板一致。
  static const TextStyle _eyebrowStyle = TextStyle(
    color: Color(0x4DFFFFFF),
    fontSize: 10,
    letterSpacing: 0.14,
  );

  /// AI 识别分区：按命名空间分组的识别标签胶囊。
  List<Widget> _buildAiSection(BuildContext context) {
    final analysis = photo.contentAnalysis;
    if (analysis?.labels.isNotEmpty != true) {
      return const [];
    }
    return [
      const SizedBox(height: 24),
      Text(
        AppLocalizations.of(context).photosAIRecognition,
        style: _eyebrowStyle,
      ),
      const SizedBox(height: 12),
      for (final entry in analysis!.labelsByNamespace.entries) ...[
        Text(
          _localizedPhotoAnalysisNamespace(context, entry.key),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final label in entry.value)
              _InfoPill(
                text: _localizedPhotoContentLabel(context, label.code),
                background: _pillBackground,
                foreground: _pillForeground,
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    ];
  }

  /// 描述分区：照片备注文本。
  List<Widget> _buildDescriptionSection(BuildContext context) {
    final description = photo.description;
    if (description == null || description.isEmpty) {
      return const [];
    }
    return [
      const SizedBox(height: 24),
      Text(
        AppLocalizations.of(context).photosDescription,
        style: _eyebrowStyle,
      ),
      const SizedBox(height: 8),
      Text(
        description,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.75),
          fontSize: 13,
          height: 18 / 13,
        ),
      ),
    ];
  }

  /// 标签分区：可移除的用户标签胶囊与添加入口。
  Widget _buildTagSection(BuildContext context, WidgetRef ref) {
    final colors = context.frameColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(AppLocalizations.of(context).photosTag, style: _eyebrowStyle),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tag in photo.tags)
              _InfoPill(
                text: _localizedPhotoAiCategory(context, tag),
                background: _pillBackground,
                foreground: _pillForeground,
                onRemoved: () async {
                  try {
                    await ref
                        .read(photoCenterControllerProvider.notifier)
                        .removeTag(photo.id, tag);
                    if (!context.mounted) return;
                    ref.invalidate(photoDetailProvider(photo.id));
                  } on Exception {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLocalizations.of(context).photosDeleteTagFailed,
                        ),
                      ),
                    );
                  }
                },
              ),
            _InfoPill(
              text: AppLocalizations.of(context).photosAddTag,
              background: colors.accent.withValues(alpha: 0.12),
              foreground: colors.accent,
              icon: Icons.add,
              onRemoved: () => _showAddTagDialog(context, ref),
            ),
          ],
        ),
      ],
    );
  }

  /// 切换收藏；成功后刷新详情数据（与顶栏心形同一数据路径）。
  Future<void> _toggleFavorite(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .toggleFavorite(photo.id, currentFavorite: photo.favorite);
      if (!context.mounted) return;
      ref.invalidate(photoDetailProvider(photo.id));
    } on Exception {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).photosOperationFailed),
        ),
      );
    }
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
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).photosAddTagFailed),
          ),
        );
      }
    }
  }
}

/// 设计稿标签胶囊：全圆角、半透明白底、可带关闭或加号动作（恒暗配色）。
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
