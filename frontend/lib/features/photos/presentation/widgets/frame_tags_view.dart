import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_empty_view.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_masonry_grid.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';

/// Frame 标签视图：标签芯片 + 选中标签的照片瀑布流。
///
/// 标签清单与各标签的照片均为进入视图时的实时查询，添加/移除标签后
/// 重新进入即回显。
class FrameTagsView extends ConsumerStatefulWidget {
  const FrameTagsView({
    required this.onOpenPhoto,
    required this.onToggleFavorite,
    super.key,
  });

  final ValueChanged<PhotoItem> onOpenPhoto;
  final ValueChanged<PhotoItem> onToggleFavorite;

  @override
  ConsumerState<FrameTagsView> createState() => _FrameTagsViewState();
}

class _FrameTagsViewState extends ConsumerState<FrameTagsView> {
  String? _selectedTag;

  @override
  Widget build(BuildContext context) {
    final colors = context.frameColors;
    final tagsAsync = ref.watch(photoTagsProvider);
    return tagsAsync.when(
      loading:
          () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error:
          (error, _) => Center(
            child: Text(
              AppLocalizations.of(context).photosOperationFailed,
              style: TextStyle(color: colors.sub, fontSize: 14),
            ),
          ),
      data:
          (tags) =>
              tags.isEmpty
                  ? FrameEmptyView(
                    icon: Icons.sell_outlined,
                    message: AppLocalizations.of(context).photosFrameTagsEmpty,
                    hint: AppLocalizations.of(context).photosFrameTagsEmptyHint,
                  )
                  : _buildContent(context, tags),
    );
  }

  Widget _buildContent(BuildContext context, List<String> tags) {
    final colors = context.frameColors;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.photosFrameNavTags,
                style: TextStyle(
                  fontFamily: FramePalette.serifFamily,
                  fontFamilyFallback: FramePalette.serifFallback,
                  color: colors.ink,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 16),
              // 芯片数量多时限制头部高度并内部滚动，避免挤压照片区。
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in tags)
                        _TagChip(
                          tag: tag,
                          selected: _selectedTag == tag,
                          onTap:
                              () => setState(
                                () =>
                                    _selectedTag =
                                        _selectedTag == tag ? null : tag,
                              ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child:
              _selectedTag == null
                  ? Center(
                    child: Text(
                      l10n.photosTagsSelectHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.muted, fontSize: 13),
                    ),
                  )
                  : _TagPhotos(
                    key: ValueKey('tag-photos-$_selectedTag'),
                    tag: _selectedTag!,
                    onOpenPhoto: (photo) {
                      ref
                          .read(photoBrowseScopeProvider.notifier)
                          .set(
                            ref
                                    .read(photosByTagProvider(_selectedTag!))
                                    .value ??
                                const <PhotoItem>[],
                            PhotoBrowseSource.tag,
                            sourceKey: _selectedTag,
                          );
                      widget.onOpenPhoto(photo);
                    },
                    onToggleFavorite: widget.onToggleFavorite,
                  ),
        ),
      ],
    );
  }
}

/// 选中标签的照片瀑布流。
class _TagPhotos extends ConsumerWidget {
  const _TagPhotos({
    required this.tag,
    required this.onOpenPhoto,
    required this.onToggleFavorite,
    super.key,
  });

  final String tag;
  final ValueChanged<PhotoItem> onOpenPhoto;
  final ValueChanged<PhotoItem> onToggleFavorite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.frameColors;
    final photosAsync = ref.watch(photosByTagProvider(tag));
    return photosAsync.when(
      loading:
          () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      error:
          (error, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              AppLocalizations.of(context).photosOperationFailed,
              style: TextStyle(color: colors.sub, fontSize: 13),
            ),
          ),
      data:
          (photos) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '#$tag',
                      style: TextStyle(
                        fontFamily: FramePalette.serifFamily,
                        fontFamilyFallback: FramePalette.serifFallback,
                        color: colors.ink,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      AppLocalizations.of(
                        context,
                      ).photosTagsPhotoCount(photos.length),
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FrameMasonryGrid(
                  photos: photos,
                  onOpenPhoto: onOpenPhoto,
                  onToggleFavorite: onToggleFavorite,
                ),
              ),
            ],
          ),
    );
  }
}

/// 标签芯片：白底细边框，选中陶土色底与文字（设计稿 tags 样式）。
class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.tag,
    required this.selected,
    required this.onTap,
  });

  final String tag;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.frameColors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration:
              MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? FramePalette.chipActiveBg : colors.searchFill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? colors.accent : colors.border),
          ),
          child: Text(
            tag,
            style: TextStyle(
              color: selected ? colors.accent : colors.sub,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
