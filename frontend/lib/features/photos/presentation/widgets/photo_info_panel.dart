import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_common_widgets.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_info_row.dart';

/// 信息侧栏宽度：与分享侧栏一致（幻灯片与详情页共用）。
const double photoInfoPanelWidth = 320;

/// 照片信息面板：幻灯片与详情页共用的恒暗信息侧栏内容。
///
/// 视觉规格：0A0A0A 面板底、PHOTO INFO 眉题 + 标题头部、
/// `buildPhotoInfoEntries` 平铺字段行（有值才渲染）、AI 识别 / 描述 /
/// 标签分区（数据存在时渲染）、底部 Like/Share 操作。
///
/// 收藏与标签等状态经详情 provider 读取，切换后面板立即回显。
class PhotoInfoPanel extends ConsumerWidget {
  const PhotoInfoPanel({required this.photo, required this.onShare, super.key});

  final PhotoItem photo;

  /// 底部 Share 按钮：由宿主关闭信息面板并打开分享侧栏。
  final VoidCallback onShare;

  static const Color _panelColor = Color(0xF00A0A0A);
  static const Color _borderColor = Color(0x12FFFFFF);
  static const Color _pillBackground = Color(0x12FFFFFF);
  static const Color _pillForeground = Color(0x99FFFFFF);

  /// 眉题/分区标题样式。
  static const TextStyle _eyebrowStyle = TextStyle(
    color: Color(0x4DFFFFFF),
    fontSize: 10,
    letterSpacing: 0.14,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final preferZh = Localizations.localeOf(context).languageCode == 'zh';
    // 收藏/标签等字段以详情 provider 的最新数据为准，切换后立即回显。
    final fresh =
        ref.watch(photoDetailProvider(photo.id)).asData?.value ?? photo;
    final rows = buildPhotoInfoEntries(fresh, l10n, preferZh: preferZh);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: _panelColor,
        border: Border(left: BorderSide(color: _borderColor)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 68, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.photosPhotoInfo, style: _eyebrowStyle),
            const SizedBox(height: 4),
            Text(
              fresh.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
            ..._buildAiSection(context, fresh),
            ..._buildDescriptionSection(context, fresh),
            _buildTagSection(context, ref, fresh),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: PhotoPanelActionButton(
                    icon:
                        fresh.favorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                    iconColor:
                        fresh.favorite
                            ? const Color(0xFFFB7185)
                            : Colors.white.withValues(alpha: 0.80),
                    label:
                        fresh.favorite
                            ? AppLocalizations.of(context).photosUnfavorite
                            : AppLocalizations.of(context).photosFavorite,
                    onTap: () => _toggleFavorite(context, ref, fresh),
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

  /// 切换收藏；成功后刷新详情数据，面板经 provider watch 自动回显。
  Future<void> _toggleFavorite(
    BuildContext context,
    WidgetRef ref,
    PhotoItem fresh,
  ) async {
    try {
      await ref
          .read(photoCenterControllerProvider.notifier)
          .toggleFavorite(fresh.id, currentFavorite: fresh.favorite);
      if (!context.mounted) return;
      ref.invalidate(photoDetailProvider(fresh.id));
    } on Exception {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).photosOperationFailed),
        ),
      );
    }
  }

  /// AI 识别分区：按命名空间分组的识别标签胶囊。
  List<Widget> _buildAiSection(BuildContext context, PhotoItem fresh) {
    final analysis = fresh.contentAnalysis;
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
  List<Widget> _buildDescriptionSection(BuildContext context, PhotoItem fresh) {
    final description = fresh.description;
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
  Widget _buildTagSection(
    BuildContext context,
    WidgetRef ref,
    PhotoItem fresh,
  ) {
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
            for (final tag in fresh.tags)
              _InfoPill(
                text: _localizedPhotoAiCategory(context, tag),
                background: _pillBackground,
                foreground: _pillForeground,
                onRemoved: () async {
                  try {
                    await ref
                        .read(photoCenterControllerProvider.notifier)
                        .removeTag(fresh.id, tag);
                    if (!context.mounted) return;
                    ref.invalidate(photoDetailProvider(fresh.id));
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
              onRemoved: () => _showAddTagDialog(context, ref, fresh.id),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showAddTagDialog(
    BuildContext context,
    WidgetRef ref,
    String photoId,
  ) async {
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
            .addTag(photoId, tag);
        if (!context.mounted) return;
        ref.invalidate(photoDetailProvider(photoId));
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
