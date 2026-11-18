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
    // 只订阅「首次加载中 / 加载失败」两位。拖动暗化与模糊滑杆时 state 每帧
    // 都变，整段 watch 会把取景框、素材库网格与展示方式卡一起拖进每帧重建。
    final status = ref.watch(
      appBackdropControllerProvider.select(
        (async) => (
          loading: async.isLoading && !async.hasValue,
          failed: async.hasError && !async.hasValue,
        ),
      ),
    );
    if (status.loading) {
      return const _BackdropLoadingSkeleton();
    }
    if (status.failed) {
      return DesktopCard(
        child: DesktopEmpty(
          icon: DesktopIcons.image,
          message: l10n.portalLocalBackdropLoadFailed,
          actionLabel: l10n.commonRetry,
          onAction: () => ref.invalidate(appBackdropControllerProvider),
        ),
      );
    }
    // 三张卡各自订阅自己需要的切片：滑杆只在展示方式卡里，取景框只跟选中
    // 素材与暗化/模糊有关，素材库只在素材集合变化时才重建。
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BackdropMasterCard(),
        _BackdropLibraryCard(),
        _BackdropPresentationCard(),
      ],
    );
  }
}

class _BackdropLoadingSkeleton extends StatelessWidget {
  const _BackdropLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DesktopSkeletonBox(width: 164, height: 14),
                        SizedBox(height: 7),
                        DesktopSkeletonBox(width: 280, height: 10),
                      ],
                    ),
                  ),
                  DesktopSkeletonBox(width: 40, height: 22, radius: 12),
                ],
              ),
              const SizedBox(height: 16),
              const AspectRatio(
                aspectRatio: 16 / 6.2,
                child: DesktopSkeletonBox(radius: 12),
              ),
              const SizedBox(height: 10),
              const Row(
                children: [
                  Expanded(child: DesktopSkeletonBox(width: 160, height: 12)),
                  SizedBox(width: 16),
                  DesktopSkeletonBox(width: 110, height: 10),
                ],
              ),
            ],
          ),
        ),
        DesktopCard(
          title: l10n.desktopBackdropLibrary,
          action: const DesktopSkeletonBox(width: 82, height: 32, radius: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DesktopSkeletonBox(width: 390, height: 11),
              const SizedBox(height: 14),
              const Row(
                children: [
                  DesktopSkeletonBox(width: 260, height: 30, radius: 12),
                  Spacer(),
                  DesktopSkeletonBox(width: 190, height: 10),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 12.0;
                  final columns = ((constraints.maxWidth + gap) / (150 + gap))
                      .floor()
                      .clamp(1, 6);
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (var index = 0; index < columns * 2; index++)
                        SizedBox(
                          width: width,
                          child: AspectRatio(
                            aspectRatio: 16 / 10,
                            child: DesktopSkeletonBox(radius: 10, index: index),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        DesktopCard(
          title: l10n.desktopBackdropPresentation,
          child: Column(
            children: [
              for (final width in [190.0, 170.0, 150.0, 210.0, 160.0])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DesktopSkeletonBox(width: 98, height: 12),
                            SizedBox(height: 6),
                            DesktopSkeletonBox(width: 180, height: 9),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      DesktopSkeletonBox(width: width, height: 30, radius: 12),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
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
  const _BackdropMasterCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appBackdropControllerProvider).value;
    if (state == null) {
      return const SizedBox.shrink();
    }
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
                        // 取景框是默认作用域下唯一能看到模糊效果的地方；
                        // 视频壁纸在壁纸层不做全屏模糊，这里同样不糊。
                        blurSigma: selected.isVideo ? 0 : settings.blurAmount,
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

class _BackdropPresentationCard extends ConsumerWidget {
  const _BackdropPresentationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appBackdropControllerProvider).value;
    if (state == null) {
      return const SizedBox.shrink();
    }
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
