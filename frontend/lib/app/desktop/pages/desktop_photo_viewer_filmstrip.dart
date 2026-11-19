part of 'desktop_photo_viewer_page.dart';

/// 底部胶片条（样例 `.vw-info`）：玻璃底 + 缩略图横排。
///
/// 从主库拆出，避免查看器越过 800 行源码棘轮；依赖仍走主库 import。
class _Filmstrip extends StatelessWidget {
  const _Filmstrip({
    required this.photos,
    required this.currentId,
    required this.onPick,
  });

  final List<PhotoItem> photos;
  final String currentId;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    // 样例 `.vw-filmstrip`：条本身没有玻璃胶囊，只有一条从透明到底部
    // 暗色的渐变遮罩；缩略图固定 64×44，未选中压到 45% 不透明度，
    // 选中上移 5px 放大 1.12 并套 2px 强调环。
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            // 样例 polish.css:335 是 `rgba(0,0,0,.35)`，不是白色高光；
            // 之前误取 `onStage`（白）导致底部整片白色渐变光。
            const Color(0x59000000),
          ],
        ),
      ),
      // 横向 ListView 必须有确定的高度：缩略图 44 高，选中态上移 5px
      // 仍在盒内，靠 overflow 留白而不是撑高整条胶片。
      child: Center(
        child: SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            shrinkWrap: true,
            itemCount: photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final active = photos[i].id == currentId;
              return GestureDetector(
                key: ValueKey<String>('viewer-thumb-${photos[i].id}'),
                onTap: () => onPick(photos[i].id),
                child: AnimatedContainer(
                  duration: DesktopMotion.of(context, DesktopMotion.soft),
                  curve: DesktopMotion.spring,
                  width: 64,
                  height: 44,
                  transform:
                      active
                          ? Matrix4.translationValues(0, -5, 0)
                          : Matrix4.identity(),
                  transformAlignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      DesktopMetrics.radiusSmall,
                    ),
                    boxShadow:
                        active
                            ? [
                              BoxShadow(
                                color: skin.accent,
                                blurRadius: 0,
                                spreadRadius: 2,
                              ),
                            ]
                            : null,
                  ),
                  child: Opacity(
                    opacity: active ? 1 : 0.45,
                    child: Transform.scale(
                      scale: active ? 1.12 : 1,
                      child: DesktopImage(
                        url: photos[i].coverUrl,
                        cacheWidth: 256,
                        fallbackIcon: DesktopIcons.image,
                        borderRadius: BorderRadius.circular(
                          DesktopMetrics.radiusSmall,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
