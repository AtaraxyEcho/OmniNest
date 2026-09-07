import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/photos/application/photo_center_models.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_dialogs.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_empty_view.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_view_meta.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_thumb_image.dart';

/// Frame 回收站视图：衬线标题 + 计数说明 + 清空按钮 + 暗化瀑布流。
///
/// 图格悬停显示恢复/永久删除按钮；照片进入回收站保留 30 天。
class FrameTrashView extends StatefulWidget {
  const FrameTrashView({
    required this.photos,
    required this.isLoading,
    required this.onRestore,
    required this.onDeleteForever,
    required this.onEmptyTrash,
    this.errorMessage,
    super.key,
  });

  final List<PhotoItem> photos;
  final bool isLoading;
  final String? errorMessage;
  final ValueChanged<PhotoItem> onRestore;
  final ValueChanged<PhotoItem> onDeleteForever;
  final VoidCallback onEmptyTrash;

  @override
  State<FrameTrashView> createState() => _FrameTrashViewState();
}

class _FrameTrashViewState extends State<FrameTrashView> {
  Future<void> _confirmEmptyTrash() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showFrameConfirmDialog(
      context,
      title: l10n.photosEmptyTrashConfirmTitle,
      body: l10n.photosEmptyTrashConfirmBody(widget.photos.length),
      confirmLabel: l10n.photosDeleteForever,
      destructive: true,
    );
    if (confirmed) {
      widget.onEmptyTrash();
    }
  }

  Future<void> _confirmDeleteForever(PhotoItem photo) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showFrameConfirmDialog(
      context,
      title: l10n.photosDeleteForeverConfirmTitle,
      body: l10n.photosDeleteForeverConfirmBody,
      confirmLabel: l10n.photosDeleteForever,
      destructive: true,
    );
    if (confirmed) {
      widget.onDeleteForever(photo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.frameColors;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverLayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.crossAxisExtent > 768 ? 24.0 : 16.0;
            final columns =
                constraints.crossAxisExtent > 1280
                    ? 4
                    : constraints.crossAxisExtent > 900
                    ? 3
                    : 2;
            return SliverPadding(
              padding: EdgeInsets.all(padding),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              frameViewLabel(l10n, FrameView.trash),
                              style: TextStyle(
                                fontFamily: FramePalette.serifFamily,
                                fontFamilyFallback: FramePalette.serifFallback,
                                color: colors.ink,
                                fontSize: 24,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.photosTrashSubtitle(widget.photos.length),
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.photos.isNotEmpty)
                        _EmptyTrashButton(onTap: _confirmEmptyTrash),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (widget.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        widget.errorMessage!,
                        style: TextStyle(
                          color: const Color(0xFFEF4444),
                          fontSize: 13,
                        ),
                      ),
                    )
                  else if (widget.photos.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 64),
                      child: FrameEmptyView(
                        icon: Icons.delete_outlined,
                        message: l10n.photosFrameTrashEmpty,
                        hint: l10n.photosFrameTrashEmptyHint,
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, gridConstraints) {
                        final gap = 10.0;
                        final itemWidth =
                            (gridConstraints.maxWidth - (columns - 1) * gap) /
                            columns;
                        return Wrap(
                          spacing: gap,
                          runSpacing: 14,
                          children: [
                            for (final photo in widget.photos)
                              SizedBox(
                                width: itemWidth,
                                child: _TrashTile(
                                  key: ValueKey('trash-${photo.id}'),
                                  photo: photo,
                                  onRestore: () => widget.onRestore(photo),
                                  onDeleteForever:
                                      () => _confirmDeleteForever(photo),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                ]),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// 清空回收站按钮：红色文字，悬停浅红底。
class _EmptyTrashButton extends StatefulWidget {
  const _EmptyTrashButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_EmptyTrashButton> createState() => _EmptyTrashButtonState();
}

class _EmptyTrashButtonState extends State<_EmptyTrashButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color:
                _hovering
                    ? const Color(0xFFEF4444).withValues(alpha: 0.08)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            AppLocalizations.of(context).photosEmptyTrash,
            style: const TextStyle(color: Color(0xFFEF4444), fontSize: 14),
          ),
        ),
      ),
    );
  }
}

/// 回收站图格：图片暗化，悬停显示恢复/永久删除按钮，底部显示标题。
class _TrashTile extends StatefulWidget {
  const _TrashTile({
    required this.photo,
    required this.onRestore,
    required this.onDeleteForever,
    super.key,
  });

  final PhotoItem photo;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;

  @override
  State<_TrashTile> createState() => _TrashTileState();
}

class _TrashTileState extends State<_TrashTile> {
  bool _hovering = false;

  double get _aspectRatio {
    final width = widget.photo.width;
    final height = widget.photo.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return 1.0;
    }
    return (width / height).clamp(0.6, 2.4);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.frameColors;
    final photo = widget.photo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: AspectRatio(
            aspectRatio: _aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: 0.7,
                  child:
                      photo.hasCover
                          ? PhotoThumbImage(
                            imageUrl: photo.coverUrl!,
                            cacheKey: photo.coverCacheKey,
                          )
                          : ColoredBox(color: colors.card),
                ),
                Positioned.fill(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.basic,
                    onEnter: (_) => setState(() => _hovering = true),
                    onExit: (_) => setState(() => _hovering = false),
                    child: AnimatedOpacity(
                      opacity: _hovering ? 1 : 0,
                      duration:
                          MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 150),
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.35),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _TrashPillButton(
                                icon: Icons.restore_rounded,
                                label:
                                    AppLocalizations.of(context).photosRestore,
                                background: Colors.white,
                                foreground: FramePalette.ink,
                                onTap: widget.onRestore,
                              ),
                              const SizedBox(width: 8),
                              _TrashPillButton(
                                icon: Icons.delete_outline_rounded,
                                label:
                                    AppLocalizations.of(
                                      context,
                                    ).photosDeletePermanently,
                                background: const Color(0xFFEF4444),
                                foreground: Colors.white,
                                onTap: widget.onDeleteForever,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            photo.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.muted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// 回收站操作胶囊按钮。
class _TrashPillButton extends StatelessWidget {
  const _TrashPillButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: foreground),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
