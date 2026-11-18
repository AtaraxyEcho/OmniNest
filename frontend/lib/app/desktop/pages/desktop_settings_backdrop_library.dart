part of 'desktop_settings_page.dart';

/// 设置页「Backdrop library」卡与素材瓦片。
///
/// 与取景框、展示方式卡分文件，是为了把「素材集合 → 网格」的重建粒度
/// 单独拎出来：拖动暗化/模糊滑杆只改 settings，这里的 Record 比对相等，
/// 整片网格（含每张瓦片里的预览图）因此不会被拖进每帧重建。
enum _BackdropFilterKind { all, still, motion, mine }

class _BackdropLibraryCard extends ConsumerStatefulWidget {
  const _BackdropLibraryCard();

  @override
  ConsumerState<_BackdropLibraryCard> createState() =>
      _BackdropLibraryCardState();
}

class _BackdropLibraryCardState extends ConsumerState<_BackdropLibraryCard> {
  _BackdropFilterKind _filter = _BackdropFilterKind.all;

  static const double _quotaBytes = 1024 * 1024 * 1024;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final notifier = ref.read(appBackdropControllerProvider.notifier);
    // `AppBackdropState` 没有重写 `operator ==`，直接 `.select` 整个 state
    // 等于没有隔离；改用逐字段结构相等的 Dart Record，只挑影响网格的字段。
    final library = ref.watch(
      appBackdropControllerProvider.select((async) {
        final value = async.value;
        return (
          backdrops: value?.backdrops,
          selectedId: value?.selectedBackdropId,
          uploading: value?.uploading ?? false,
        );
      }),
    );
    final assets = library.backdrops;
    if (assets == null) {
      return const SizedBox.shrink();
    }

    bool isMine(AppBackdropAsset asset) =>
        asset.sourceType != AppBackdropSourceType.bundled;
    bool isStill(AppBackdropAsset asset) =>
        asset.mediaType != AppBackdropMediaType.video;

    final items = assets
        .where((asset) {
          return switch (_filter) {
            _BackdropFilterKind.all => true,
            _BackdropFilterKind.still => isStill(asset),
            _BackdropFilterKind.motion => !isStill(asset),
            _BackdropFilterKind.mine => isMine(asset),
          };
        })
        .toList(growable: false);
    final mine = assets.where(isMine).toList(growable: false);
    final used = assets.fold<int>(0, (sum, asset) => sum + asset.fileSize);
    final pct = used <= 0 ? 0.0 : (used / _quotaBytes).clamp(0.0, 1.0);

    return DesktopCard(
      title: l10n.desktopBackdropLibrary,
      action: DesktopButton(
        label: l10n.portalLocalBackdropAddFiles,
        icon: DesktopIcons.upload,
        variant: DesktopButtonVariant.primary,
        busy: library.uploading,
        onPressed: () => unawaited(notifier.addBackdropFiles()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              l10n.desktopBackdropLibraryDesc,
              style: DesktopType.caption(skin.text3),
            ),
          ),
          Row(
            children: [
              DesktopSeg<_BackdropFilterKind>(
                options: _BackdropFilterKind.values,
                value: _filter,
                small: true,
                labelOf:
                    (value) => switch (value) {
                      _BackdropFilterKind.all =>
                        l10n.portalLocalBackdropFilterAll,
                      _BackdropFilterKind.still =>
                        l10n.desktopBackdropFilterStatic,
                      _BackdropFilterKind.motion =>
                        l10n.desktopBackdropFilterMotion,
                      _BackdropFilterKind.mine =>
                        l10n.desktopBackdropFilterMine,
                    },
                onChanged: (value) => setState(() => _filter = value),
              ),
              const Spacer(),
              SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 4,
                    backgroundColor: skin.raise3,
                    valueColor: AlwaysStoppedAnimation<Color>(skin.accent),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${formatFileSize(used)} / 1 GB',
                style: DesktopType.caption(skin.text3),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              final columns = ((constraints.maxWidth + gap) / (150 + gap))
                  .floor()
                  .clamp(1, 6);
              final tileWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  SizedBox(
                    width: tileWidth,
                    child: _BackdropAddTile(
                      label: l10n.portalLocalBackdropDropHint,
                      onTap: () => unawaited(notifier.addBackdropFiles()),
                    ),
                  ),
                  for (final asset in items)
                    SizedBox(
                      width: tileWidth,
                      child: _BackdropTile(
                        asset: asset,
                        selected: library.selectedId == asset.id,
                        removable: isMine(asset),
                        onSelect:
                            () => unawaited(notifier.selectBackdrop(asset.id)),
                        onRemove:
                            () => unawaited(notifier.removeBackdrop(asset.id)),
                      ),
                    ),
                ],
              );
            },
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Text(
                _filter == _BackdropFilterKind.mine
                    ? l10n.desktopBackdropNoUploads
                    : l10n.portalLocalBackdropFilterEmpty,
                style: DesktopType.caption(skin.text3),
              ),
            ),
          if (mine.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  Text(
                    l10n.portalLocalBackdropCount(mine.length),
                    style: DesktopType.caption(skin.text3),
                  ),
                  const Spacer(),
                  DesktopButton(
                    label: l10n.desktopBackdropClearUploads,
                    onPressed: () => _confirmClear(context, ref, mine.length),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    WidgetRef ref,
    int count,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDesktopDialog<bool>(
      context,
      builder:
          (dialogContext) => DesktopDialog(
            title: l10n.desktopBackdropClearUploads,
            content: Text(
              l10n.desktopBackdropClearUploadsBody(count),
              style: DesktopType.body(DesktopSkin.of(dialogContext).text2),
            ),
            actions: [
              DesktopButton(
                label: l10n.desktopCancel,
                onPressed: () => closeDesktopModal(dialogContext, false),
              ),
              DesktopButton(
                label: l10n.desktopBackdropClearUploads,
                variant: DesktopButtonVariant.danger,
                onPressed: () => closeDesktopModal(dialogContext, true),
              ),
            ],
          ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(appBackdropControllerProvider.notifier).clearBackdrops();
  }
}

class _BackdropAddTile extends StatelessWidget {
  const _BackdropAddTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: DesktopHover(
        builder:
            (context, hovered) => GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: DesktopMotion.of(context, DesktopMotion.fast),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DesktopMetrics.radius),
                  border: Border.all(
                    color: hovered ? skin.accent : skin.line2,
                    width: 1.5,
                  ),
                  color: hovered ? skin.raise : Colors.transparent,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      DesktopIcons.plus,
                      size: 22,
                      color: hovered ? skin.accent : skin.text3,
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.micro(
                          hovered ? skin.accent : skin.text3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }
}

class _BackdropTile extends StatelessWidget {
  const _BackdropTile({
    required this.asset,
    required this.selected,
    required this.removable,
    required this.onSelect,
    required this.onRemove,
  });

  final AppBackdropAsset asset;
  final bool selected;
  final bool removable;
  final VoidCallback onSelect;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 10,
          child: DesktopHover(
            builder:
                (context, hovered) => GestureDetector(
                  onTap: onSelect,
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: DesktopMotion.of(context, DesktopMotion.fast),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        DesktopMetrics.radius,
                      ),
                      border: Border.all(
                        color: selected ? skin.accent : Colors.transparent,
                        width: 2,
                      ),
                      boxShadow:
                          selected
                              ? [
                                BoxShadow(
                                  color: skin.accent.withValues(alpha: 0.22),
                                  blurRadius: 0,
                                  spreadRadius: 3,
                                ),
                              ]
                              : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        DesktopMetrics.radius - 2,
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          BackdropTilePreview(backdrop: asset),
                          // 类型角标（样例 `.bd-kind`）。
                          Positioned(
                            left: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: DesktopPalette.onStage.withValues(
                                  alpha: 0.65,
                                ),
                                borderRadius: BorderRadius.circular(
                                  DesktopMetrics.radiusPill,
                                ),
                              ),
                              child: Text(
                                _kindLabel(l10n, asset),
                                style: DesktopType.micro(Colors.white),
                              ),
                            ),
                          ),
                          if (selected)
                            Positioned(
                              right: 6,
                              bottom: 6,
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: skin.accent,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  DesktopIcons.check,
                                  size: 13,
                                  color: skin.accentInk,
                                ),
                              ),
                            ),
                          if (removable && hovered)
                            Positioned(
                              right: 4,
                              top: 4,
                              child: DesktopIconButton(
                                icon: DesktopIcons.trash,
                                size: 24,
                                iconSize: 13,
                                tooltip: l10n.portalLocalBackdropRemove,
                                onPressed: onRemove,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          asset.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DesktopType.caption(skin.text2),
        ),
      ],
    );
  }
}
