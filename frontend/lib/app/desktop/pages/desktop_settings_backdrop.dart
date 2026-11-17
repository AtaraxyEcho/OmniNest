part of 'desktop_settings_page.dart';

/// 设置页的「Backdrop library」分区（样例 `BackdropView.tsx` 的
/// `BackdropSettings`）。
///
/// 三张卡与样例一一对应：启用与预览 / 背景库 / 显示方式。数据全部走
/// 现有的 `appBackdropControllerProvider`，桌面与移动共用同一份服务端
/// 素材库，不另建一套。
class _BackdropSection extends ConsumerWidget {
  const _BackdropSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(appBackdropControllerProvider);
    return async.when(
      loading:
          () => DesktopCard(
            child: SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  l10n.portalLocalBackdropProcessing,
                  style: DesktopType.caption(DesktopSkin.of(context).text3),
                ),
              ),
            ),
          ),
      error:
          (error, stack) => DesktopCard(
            child: DesktopEmpty(
              icon: DesktopIcons.image,
              message: l10n.portalLocalBackdropLoadFailed,
            ),
          ),
      data:
          (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BackdropMasterCard(state: state),
              _BackdropLibraryCard(state: state),
              _BackdropPresentationCard(state: state),
            ],
          ),
    );
  }
}

/// 卡片里的一行：左侧标题 + 说明，右侧控件（样例 `.set-row`）。
class _BackdropRow extends StatelessWidget {
  const _BackdropRow({
    required this.title,
    this.description,
    required this.trailing,
  });

  final String title;
  final String? description;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: DesktopType.rowTitle(skin.text)),
                if (description != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      description!,
                      style: DesktopType.caption(skin.text3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          trailing,
        ],
      ),
    );
  }
}

class _BackdropMasterCard extends ConsumerWidget {
  const _BackdropMasterCard({required this.state});

  final AppBackdropState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final notifier = ref.read(appBackdropControllerProvider.notifier);
    final settings = state.settings;
    final selected = state.selectedBackdrop;
    return DesktopCard(
      title: l10n.desktopBackdropUse,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BackdropRow(
            title: l10n.portalLocalBackdropEnable,
            description:
                settings.enabled
                    ? l10n.desktopBackdropUseOn
                    : l10n.desktopBackdropUseOff,
            trailing: DesktopToggle(
              value: settings.enabled,
              label: l10n.portalLocalBackdropEnable,
              onChanged: (value) => unawaited(notifier.setEnabled(value)),
            ),
          ),
          // 样例 `.bd-screen`：16/6.2 的取景框 + 三块 mock 结构，让用户
          // 在真正切换前就看清壁纸压在界面后面的观感。
          ClipRRect(
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusPop),
            child: AspectRatio(
              aspectRatio: 16 / 6.2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: DesktopPalette.onStage,
                  border: Border.all(color: skin.line2),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (selected != null)
                      BackdropTilePreview(
                        backdrop: selected,
                        maxDecodeWidth: 1440,
                      ),
                    if (selected != null && settings.dimAmount > 0.01)
                      ColoredBox(
                        color: DesktopPalette.onStage.withValues(
                          alpha: settings.dimAmount,
                        ),
                      ),
                    // mock 侧栏与两张卡：比例照样例 17% / 44×30% / 28×28%。
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: 0.17,
                        child: ColoredBox(
                          color: DesktopPalette.onStage.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    Align(
                      alignment: const Alignment(-0.42, -0.5),
                      child: FractionallySizedBox(
                        widthFactor: 0.44,
                        heightFactor: 0.3,
                        child: _mockPanel(skin: skin),
                      ),
                    ),
                    Align(
                      alignment: const Alignment(-0.42, 0.34),
                      child: FractionallySizedBox(
                        widthFactor: 0.28,
                        heightFactor: 0.28,
                        child: _mockPanel(skin: skin),
                      ),
                    ),
                    if (!settings.enabled)
                      ColoredBox(
                        color: DesktopPalette.onStage.withValues(alpha: 0.82),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                DesktopIcons.sparkle,
                                size: 16,
                                color: skin.text2,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.desktopBackdropDefaultScene,
                                style: DesktopType.caption(skin.text2),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  selected?.title ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.denseStrong(skin.text),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                selected == null
                    ? ''
                    : [
                      _kindLabel(l10n, selected),
                      if (selected.sourceType == AppBackdropSourceType.bundled)
                        l10n.desktopBackdropBuiltin
                      else if (selected.fileSize > 0)
                        formatFileSize(selected.fileSize),
                    ].join(' · '),
                style: DesktopType.caption(skin.text3),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mockPanel({required DesktopSkin skin}) => DecoratedBox(
    decoration: BoxDecoration(
      color: DesktopPalette.onStage.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: DesktopPalette.onStage.withValues(alpha: 0.20)),
    ),
  );
}

enum _BackdropFilterKind { all, still, motion, mine }

class _BackdropLibraryCard extends ConsumerStatefulWidget {
  const _BackdropLibraryCard({required this.state});

  final AppBackdropState state;

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
    final state = widget.state;

    bool isMine(AppBackdropAsset asset) =>
        asset.sourceType != AppBackdropSourceType.bundled;
    bool isStill(AppBackdropAsset asset) =>
        asset.mediaType != AppBackdropMediaType.video;

    final items = state.backdrops
        .where((asset) {
          return switch (_filter) {
            _BackdropFilterKind.all => true,
            _BackdropFilterKind.still => isStill(asset),
            _BackdropFilterKind.motion => !isStill(asset),
            _BackdropFilterKind.mine => isMine(asset),
          };
        })
        .toList(growable: false);
    final mine = state.backdrops.where(isMine).toList(growable: false);
    final used = state.backdrops.fold<int>(
      0,
      (sum, asset) => sum + asset.fileSize,
    );
    final pct = used <= 0 ? 0.0 : (used / _quotaBytes).clamp(0.0, 1.0);

    return DesktopCard(
      title: l10n.desktopBackdropLibrary,
      action: DesktopButton(
        label: l10n.portalLocalBackdropAddFiles,
        icon: DesktopIcons.upload,
        variant: DesktopButtonVariant.primary,
        busy: state.uploading,
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
                        selected: state.selectedBackdropId == asset.id,
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

class _BackdropPresentationCard extends ConsumerWidget {
  const _BackdropPresentationCard({required this.state});

  final AppBackdropState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final notifier = ref.read(appBackdropControllerProvider.notifier);
    final settings = state.settings;
    final scope = ref.watch(desktopBackdropScopeProvider);
    final scopeController = ref.read(desktopBackdropScopeProvider.notifier);
    return DesktopCard(
      title: l10n.desktopBackdropPresentation,
      action: DesktopButton(
        label: l10n.desktopBackdropReset,
        icon: DesktopIcons.undo,
        onPressed: () {
          unawaited(notifier.setFit(AppBackdropFit.cover));
          unawaited(notifier.setAlignment(AppBackdropAlignment.center));
          unawaited(notifier.setDimAmount(0.35));
          unawaited(notifier.setBlurAmount(0));
          unawaited(notifier.setVideoMuted(true));
          unawaited(scopeController.select(DesktopBackdropScope.homeMusic));
          showDesktopToast(
            context,
            l10n.desktopBackdropResetDone,
            icon: DesktopIcons.undo,
          );
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BackdropRow(
            title: l10n.desktopBackdropApplyTo,
            description: l10n.desktopBackdropApplyDesc,
            trailing: DesktopSeg<DesktopBackdropScope>(
              options: DesktopBackdropScope.values,
              value: scope,
              small: true,
              labelOf:
                  (value) =>
                      value == DesktopBackdropScope.everywhere
                          ? l10n.desktopBackdropEverywhere
                          : l10n.desktopBackdropHomeMusic,
              onChanged: (value) => unawaited(scopeController.select(value)),
            ),
          ),
          _BackdropRow(
            title: l10n.portalLocalBackdropFit,
            trailing: DesktopSeg<AppBackdropFit>(
              options: const [AppBackdropFit.cover, AppBackdropFit.contain],
              value:
                  settings.fit == AppBackdropFit.contain
                      ? AppBackdropFit.contain
                      : AppBackdropFit.cover,
              small: true,
              labelOf:
                  (value) =>
                      value == AppBackdropFit.cover
                          ? l10n.portalLocalBackdropFitCover
                          : l10n.portalLocalBackdropFitContain,
              onChanged: (value) => unawaited(notifier.setFit(value)),
            ),
          ),
          _BackdropRow(
            title: l10n.portalLocalBackdropAlignment,
            trailing: DesktopSeg<AppBackdropAlignment>(
              options: AppBackdropAlignment.values,
              value: settings.alignment,
              small: true,
              labelOf:
                  (value) => switch (value) {
                    AppBackdropAlignment.top =>
                      l10n.portalLocalBackdropAlignTop,
                    AppBackdropAlignment.center =>
                      l10n.portalLocalBackdropAlignCenter,
                    AppBackdropAlignment.bottom =>
                      l10n.portalLocalBackdropAlignBottom,
                  },
              onChanged: (value) => unawaited(notifier.setAlignment(value)),
            ),
          ),
          _BackdropRow(
            title: l10n.portalLocalBackdropDim,
            trailing: Row(
              children: [
                SizedBox(
                  width: 180,
                  child: DesktopSlider(
                    value: (settings.dimAmount * 100).clamp(0, 90),
                    max: 90,
                    onChanged:
                        (value) =>
                            unawaited(notifier.setDimAmount(value / 100)),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${(settings.dimAmount * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: DesktopType.numeric(skin.text3),
                  ),
                ),
              ],
            ),
          ),
          _BackdropRow(
            title: l10n.portalLocalBackdropBlur,
            trailing: Row(
              children: [
                SizedBox(
                  width: 180,
                  child: DesktopSlider(
                    value: settings.blurAmount.clamp(0, 24),
                    max: 24,
                    onChanged:
                        (value) => unawaited(notifier.setBlurAmount(value)),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${settings.blurAmount.round()}px',
                    textAlign: TextAlign.right,
                    style: DesktopType.numeric(skin.text3),
                  ),
                ),
              ],
            ),
          ),
          _BackdropRow(
            title: l10n.portalLocalBackdropVideoMuted,
            trailing: DesktopToggle(
              value: settings.videoMuted,
              label: l10n.portalLocalBackdropVideoMuted,
              onChanged: (value) => unawaited(notifier.setVideoMuted(value)),
            ),
          ),
          _BackdropRow(
            title: l10n.portalLocalBackdropSeparateDevices,
            description: l10n.portalLocalBackdropSeparateDevicesHint,
            trailing: DesktopToggle(
              value: settings.separateDeviceBackdrops,
              label: l10n.portalLocalBackdropSeparateDevices,
              onChanged:
                  (value) => unawaited(notifier.setDeviceSeparation(value)),
            ),
          ),
        ],
      ),
    );
  }
}

String _kindLabel(AppLocalizations l10n, AppBackdropAsset asset) {
  return switch (asset.mediaType) {
    AppBackdropMediaType.video => l10n.desktopBackdropKindVideo,
    AppBackdropMediaType.gif => l10n.desktopBackdropKindGif,
    AppBackdropMediaType.image => l10n.desktopBackdropKindImage,
  };
}
