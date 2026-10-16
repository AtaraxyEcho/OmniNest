import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';

/// 断网横幅。
///
/// AGENTS 对 Web（含移动浏览器）的口径是"不承诺离线：断网时显示离线横幅并明确
/// 提示需要网络"。这条承诺此前只有一半：连接监听、`appOnlineStatusProvider` 与
/// 文案 `mobileOfflineBanner` 都在，但**没有任何渲染消费点**，所以断网时界面上
/// 什么都没有。本组件补上那半截。
///
/// 取根主题的色而不是 `context.env`：它挂在根 builder，位于各空间极性作用域之上，
/// 那里读极性表会拿到未注册的暗档回落。文字用 `onSurface`、警示色只做 14% 底纹
/// 与图标，两极性都可读，不靠"深色底配浅色字"的假设。
///
/// 非模态、不拦截横幅之外的手势：离线时用户仍要能浏览已加载内容与本地缓存。
class OfflineBannerLayer extends ConsumerWidget {
  const OfflineBannerLayer({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // null = 尚未收到首个连接事件，或平台不支持监听：不闪提示。
    final online = ref.watch(appOnlineStatusProvider).value ?? true;
    if (online) {
      return child;
    }
    final colors = Theme.of(context).colorScheme;
    final warning =
        Theme.of(context).extension<GlobalThemeColors>()?.warning ??
        colors.error;
    final message = AppLocalizations.of(context).mobileOfflineBanner;
    return Stack(
      children: [
        child,
        Positioned(
          top: MediaQuery.paddingOf(context).top,
          left: 0,
          right: 0,
          child: Semantics(
            liveRegion: true,
            label: message,
            child: ColoredBox(
              color: Color.alphaBlend(
                warning.withValues(alpha: 0.14),
                colors.surface,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 18, color: warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: AppTypography.bodyMedium,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
