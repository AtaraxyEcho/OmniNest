import 'package:flutter/material.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_thumb_image.dart';

/// 照片模块子页的托管形态判定。
///
/// `/photos/albums/:id`、`/photos/:id` 等根级推入路由未经 `MobileHostedRoute`
/// 包裹，取不到壳层 scope；这里按壳层同一规则回退判定，避免移动端子页
/// 仍落回工位皮肤。已有作用域时以作用域取值为准（壳层与测试都用显式
/// 作用域声明形态，不受推导影响）。
bool photosHostedForm(BuildContext context) {
  final scope = context.findAncestorWidgetOfExactType<MobileShellScope>();
  if (scope != null) {
    return scope.hosted;
  }
  return shouldUseResponsiveMobileShell(
    mobilePlatform: isMobilePlatform,
    width: MediaQuery.sizeOf(context).width,
  );
}

/// 托管形态作用域：把推导出的 hosted 标记补挂到页面子树。
///
/// `MobilePageSurface`、工位弹窗分流等共享组件按 scope 取值，缺 scope 时
/// 会退到浅色 pageMask；补挂后子页与 `/photos` 主页表现一致。非托管原样
/// 透传，桌面形态不受影响。
class PhotoHostedScope extends StatelessWidget {
  const PhotoHostedScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!photosHostedForm(context)) {
      return child;
    }
    return MobileShellScope(hosted: true, child: child);
  }
}

/// 样例 `.album-toolbar` / `.photo-toolbar` 行：左侧 9px 弱化说明 +
/// 右侧动作组；整行最小高度 44（工具行 40 由调用方下调）。
class PhotoHostedToolbarRow extends StatelessWidget {
  const PhotoHostedToolbarRow({
    required this.label,
    this.actions = const <Widget>[],
    this.minHeight = 44,
    super.key,
  });

  final String label;
  final List<Widget> actions;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 样例 `.album-toolbar` 用 space-between 单行排列，窄屏放不下时
            // 触屏改走横向滚动：动作组最多占满可用宽度减去 96 的说明文字
            // 预留位，超出即滚动，不足即贴右。
            final actionsMaxWidth = (constraints.maxWidth - 96).clamp(
              0.0,
              constraints.maxWidth,
            );
            return Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9, // ignore: font_size_whitelist
                      color: context.env.inkMuted,
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: actionsMaxWidth),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final action in actions) ...[
                          const SizedBox(width: 7),
                          action,
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 样例工具行胶囊钮（`.album-toolbar button`）：36 高、r12、白 7% 底 +
/// 白 9% 描边、17 图标 + 9px 文字；选中态酸绿 10% 底 + 酸绿 38% 描边。
class PhotoHostedPillButton extends StatelessWidget {
  const PhotoHostedPillButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.minHeight = 36,
    this.radius = 12,
    this.iconSize = 17,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final double minHeight;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          active
              ? context.env.accentInk.withValues(alpha: 0.1)
              : context.env.line07,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(
          color:
              active
                  ? context.env.accentInk.withValues(alpha: 0.38)
                  : context.env.line09,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: iconSize, color: context.env.ink),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9, // ignore: font_size_whitelist
                    color: context.env.ink,
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

/// 样例 `.album-grid .add-tile`：整格加号入口（25% 白描边、r14、22px
/// 加号）。Flutter 边框不支持虚线，样例的 1px dashed 以同色实线等效。
class PhotoHostedAddTile extends StatelessWidget {
  const PhotoHostedAddTile({
    required this.label,
    required this.onTap,
    super.key,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MobilePressable(
      semanticLabel: label,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x08FFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x40FFFFFF)),
        ),
        child: Center(
          child: Icon(Icons.add_rounded, size: 22, color: context.env.inkFaint),
        ),
      ),
    );
  }
}

/// 样例 `.album-grid` / `.picker-grid` 方格：封面裁切填满。
///
/// `pickMode` 打开选择态（未选 opacity .55，选中 2px 酸绿内描边 +
/// 24px 对勾舱，right/top 7）；关闭时与普通相册格一致，不叠加任何浮层。
class PhotoHostedSquareTile extends StatelessWidget {
  const PhotoHostedSquareTile({
    required this.photo,
    required this.onTap,
    this.onLongPress,
    this.pickMode = false,
    this.picked = false,
    super.key,
  });

  final PhotoItem photo;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool pickMode;
  final bool picked;

  @override
  Widget build(BuildContext context) {
    final tileOpacity = pickMode ? (picked ? 1.0 : 0.55) : 1.0;
    return MobilePressable(
      semanticLabel: photo.title,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: tileOpacity,
            child:
                photo.hasCover
                    ? PhotoThumbImage(
                      imageUrl: photo.coverUrl!,
                      cacheKey: photo.coverCacheKey,
                    )
                    : const ColoredBox(color: Color(0xFF222626)),
          ),
          if (pickMode && picked)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: context.env.accentInk, width: 2),
                  ),
                ),
              ),
            ),
          if (pickMode && picked)
            Positioned(
              right: 7,
              top: 7,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.env.accent,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: 24,
                  child: Center(
                    child: OmniIcon(
                      icon: OmniIcons.check,
                      size: 14,
                      color: context.env.onAccent,
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

/// 样例 `.album-grid` 容器：三列 5px 缝方格，整块 r16 裁切、内衬归零。
///
/// 滚动由本 GridView 自身承载（分页通知由调用方在外层监听），格数固定
/// 三列，不随宽度调整——移动托管形态与样例一致。
class PhotoHostedPhotoGrid extends StatelessWidget {
  const PhotoHostedPhotoGrid({
    required this.itemCount,
    required this.itemBuilder,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 24),
    super.key,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: GridView.builder(
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 5,
            crossAxisSpacing: 5,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        ),
      ),
    );
  }
}
