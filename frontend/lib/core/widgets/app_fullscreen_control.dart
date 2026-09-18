import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 为页面范围绑定 F11 全屏快捷键。
class AppFullscreenShortcutScope extends StatelessWidget {
  const AppFullscreenShortcutScope({
    required this.onToggle,
    required this.child,
    super.key,
  });

  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.f11): onToggle,
      },
      child: child,
    );
  }
}

/// 顶部栏统一使用的全屏切换按钮。
class AppFullscreenButton extends StatelessWidget {
  const AppFullscreenButton({
    required this.isFullscreen,
    required this.foregroundColor,
    required this.accentColor,
    required this.onPressed,
    this.enterTooltip,
    this.exitTooltip,
    super.key,
  });

  final bool isFullscreen;
  final Color foregroundColor;
  final Color accentColor;
  final VoidCallback onPressed;

  /// 自定义非全屏态提示；缺省使用 F11 全屏文案。
  final String? enterTooltip;

  /// 自定义全屏态提示；缺省使用 F11 退出全屏文案。
  final String? exitTooltip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tooltip =
        isFullscreen
            ? (exitTooltip ?? l10n.fullscreenExitShortcut)
            : (enterTooltip ?? l10n.fullscreenEnterShortcut);
    final animationDuration =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false
            ? Duration.zero
            : MotionToken.fast;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: AnimatedContainer(
            duration: animationDuration,
            curve: Curves.easeOutCubic,
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: isFullscreen ? 0.18 : 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    isFullscreen
                        ? accentColor.withValues(alpha: 0.62)
                        : Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Icon(
              isFullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              size: 19,
              color: foregroundColor,
            ),
          ),
        ),
      ),
    );
  }
}
