part of 'desktop_np_style_panel.dart';

class _DarkSeg extends StatelessWidget {
  const _DarkSeg({
    required this.labels,
    required this.index,
    required this.onChanged,
    this.small = false,
    this.keyPrefix,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final bool small;

  /// 段位可寻址前缀（仅测试与无障碍定位使用，避免同屏多组分段键冲突）。
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                key:
                    keyPrefix == null
                        ? null
                        : ValueKey<String>('$keyPrefix-$i'),
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: DesktopMotion.of(context, DesktopMotion.fast),
                  padding: EdgeInsets.symmetric(
                    vertical: small ? 5 : 7,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    color:
                        i == index
                            ? Colors.white.withValues(alpha: 0.20)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: DesktopType.chip(
                      i == index
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.70),
                    ).copyWith(
                      fontSize: small ? 11.5 : 12.5,
                      fontWeight:
                          i == index ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GridChoiceButton extends StatelessWidget {
  const _GridChoiceButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.height = 32,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: DesktopMotion.of(context, DesktopMotion.fast),
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DesktopType.chip(
            selected ? const Color(0xFF0A0C0E) : const Color(0xCCFFFFFF),
          ).copyWith(
            fontSize: _npChipSize,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: DesktopMotion.of(context, DesktopMotion.fast),
        width: 38,
        height: 22,
        padding: const EdgeInsets.all(3),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: value ? Colors.white : Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: value ? const Color(0xFF0A0C0E) : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// 4 列 16:10 壁纸库选择器（样例 `WallPicker`）：
/// 带动态视频标与选中对勾，点击仅写入 `style.wallId`，绝不污染全局桌面壁纸。
class _WallPicker extends ConsumerWidget {
  const _WallPicker({required this.style, required this.onSelect});

  final DesktopNpStyle style;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(appBackdropControllerProvider).asData?.value;
    final items = state?.backdrops ?? const <AppBackdropAsset>[];
    final current =
        items.where((asset) => asset.id == style.wallId).firstOrNull ??
        items.firstOrNull;
    final selectedId = current?.id;
    final totalCells = items.length + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: totalCells,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 16 / 10,
          ),
          itemBuilder: (context, index) {
            if (index == items.length) {
              return GestureDetector(
                onTap:
                    () => unawaited(
                      ref
                          .read(appBackdropControllerProvider.notifier)
                          .addBackdropFiles(),
                    ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                      width: 1.2,
                    ),
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                  child: const Center(
                    child: Icon(
                      DesktopIcons.plus,
                      size: 18,
                      color: DesktopNpStylePanel._muted,
                    ),
                  ),
                ),
              );
            }
            final asset = items[index];
            final selected = asset.id == selectedId;
            final isAnimated =
                asset.mediaType == AppBackdropMediaType.video ||
                asset.mediaType == AppBackdropMediaType.gif;
            return GestureDetector(
              onTap: () => onSelect(asset.id),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: selected ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    BackdropTilePreview(backdrop: asset),
                    if (isAnimated)
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.65),
                          ),
                          child: const Icon(
                            DesktopIcons.play,
                            size: 9,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    if (selected)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: const Icon(
                            DesktopIcons.check,
                            size: 11,
                            color: Color(0xFF0A0C0E),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.desktopNpWallEmpty,
              style: DesktopType.caption(DesktopNpStylePanel._muted),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                current?.title ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DesktopType.caption(DesktopNpStylePanel._muted),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => desktopGo(context, DesktopRoutes.settings),
              child: Text(
                l10n.desktopNpManageLibrary,
                style: DesktopType.caption(DesktopNpStylePanel._text).copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white54,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
