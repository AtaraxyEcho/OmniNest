import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/presentation/widgets/music_platform_login_form.dart';
import 'package:omninest/app/theme/feature/music_chrome_colors.dart';

/// 平台登录底部弹出面板（跟随宿主主题：浅色实体、深色实体、浅色 + 动态壁纸的
/// 烟熏玻璃三种场景都使用 Music 已解析色阶）。
///
/// 只保留扫码登录：手机号（密码 / 短信验证码）与邮箱登录已下线。
/// 面板不再承载文本输入，无需处理键盘占位。
class PlatformLoginSheet extends ConsumerWidget {
  const PlatformLoginSheet({super.key});

  /// 卡片外固定占位（拖拽条、标题、内边距、卡片内边距与卡头）。
  static const double _sheetChromeHeight = 260;

  /// 内容区目标像素高度，按窗口高度换算为比例。
  static const double _contentTargetHeight = 300;

  /// 浅色模式抽屉底色：样例 `bg-white/90` 的白色磨砂。
  static const Color _lightSheetFill = MusicChromeColors.lightSheetFill;

  /// 品牌图标底座：样例 `bg-neutral-900` 的深色圆角块，仅用于浅色模式。
  static const Color _lightBrandTileColor = MusicChromeColors.lightBrandTile;

  static Future<void> show(BuildContext context) {
    final colors = context.musicColors;
    // 底部弹窗挂在导航器的 Overlay 上，不会自动继承 Music 页面局部的已解析主题，
    // 因此显式承接宿主主题：深色主题得到深色抽屉，浅色 + 动态壁纸得到烟熏玻璃。
    final hostTheme = Theme.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // 显式承接主题遮罩：窗口自身不透明，缺少遮罩时浅色下会和宿主页面糊在一起。
      barrierColor: colors.scrim,
      useSafeArea: true,
      builder: (_) => Theme(data: hostTheme, child: const PlatformLoginSheet()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(musicCenterControllerProvider).asData?.value;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final target =
            (_sheetChromeHeight + _contentTargetHeight) /
            (availableHeight <= 0 ? 900 : availableHeight);
        return DraggableScrollableSheet(
          initialChildSize: target.clamp(0.34, 0.94),
          minChildSize: 0.28,
          maxChildSize: 0.96,
          snap: true,
          builder: (context, scrollController) {
            return _LoginSheetChrome(
              scrollController: scrollController,
              title: l10n.musicPlatformNeteaseName,
              subtitle: l10n.musicPlatformNeteaseQrHint,
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [
                  NeteaseLoginSection(userInfo: state?.neteaseUserInfo),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// 抽屉容器：浅色按样例渲染白色磨砂 + 柔和投影 + 顶部高光线，
/// 深色沿用模块色阶的既有观感；两端的排版结构一致。
class _LoginSheetChrome extends StatelessWidget {
  const _LoginSheetChrome({
    required this.scrollController,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final ScrollController scrollController;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      foregroundDecoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color:
              isLight
                  ? Colors.white.withValues(alpha: 0.7)
                  : colors.fieldBorder.withValues(alpha: 0.6),
        ),
      ),
      decoration: BoxDecoration(
        color:
            isLight ? PlatformLoginSheet._lightSheetFill : colors.windowSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow:
            isLight
                ? <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 60,
                    offset: const Offset(0, -12),
                  ),
                ]
                : const <BoxShadow>[],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Column(
            children: [
              // 顶部高光细线（样例 `via-neutral-300/60` 渐变）。
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 48),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      Colors.transparent,
                      (isLight ? Colors.black : Colors.white).withValues(
                        alpha: 0.14,
                      ),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color:
                          isLight
                              ? Colors.black.withValues(alpha: 0.16)
                              : colors.outline.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color:
                            isLight
                                ? PlatformLoginSheet._lightBrandTileColor
                                : colors.onSurface.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.cloud_rounded,
                        color: isLight ? Colors.white : colors.onSurface,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: AppTypography.titleMedium,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: AppTypography.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _RoundCloseButton(isLight: isLight),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: colors.fieldBorder.withValues(alpha: 0.6),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// 圆形关闭按钮：样例 `w-7 h-7 rounded-full bg-neutral-100`。
class _RoundCloseButton extends StatelessWidget {
  const _RoundCloseButton({required this.isLight});

  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final l10n = AppLocalizations.of(context);
    return Tooltip(
      message: l10n.readerClose,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                isLight
                    ? Colors.black.withValues(alpha: 0.06)
                    : Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: colors.fieldBorder.withValues(alpha: 0.6),
            ),
          ),
          child: Icon(
            Icons.close_rounded,
            size: 16,
            color: colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
