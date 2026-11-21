import 'package:material_ui/material_ui.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/app/theme/feature/residual_chrome_colors.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_controls.dart';

/// 播放器顶部导航和影片上下文。
///
/// 不再在内部返回 `Positioned`，由外层 `Stack` 直接持有 `Positioned`，
/// 避免被 `AnimatedSlide` 包裹时触发 `Incorrect use of ParentDataWidget` 崩溃。
class MoviePlayerTopBar extends StatelessWidget {
  const MoviePlayerTopBar({
    required this.title,
    required this.onBack,
    required this.onInfoTap,
    required this.isMobile,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onBack;
  final VoidCallback onInfoTap;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final colors = context.videoColors;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [MovieChromeColors.playerTopBarScrim, Colors.transparent],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          // 样例 `.v-top { padding: 22px 28px 60px }`：底部大留白撑起渐变，
          // 标题压画面上方时不至于挤在窗口边缘。移动端保持紧凑。
          padding:
              isMobile
                  ? const EdgeInsets.symmetric(horizontal: 18, vertical: 12)
                  : const EdgeInsets.fromLTRB(28, 22, 28, 60),
          child: Row(
            children: [
              MoviePlayerIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: AppLocalizations.of(context).videoBackToDetail,
                onPressed: onBack,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          isMobile
                              ? TextStyle(
                                color: colors.playerControlForeground,
                                fontSize: AppTypography.titleMedium,
                                fontWeight: FontWeight.w700,
                              )
                              : DesktopType.displaySm(
                                colors.playerControlForeground,
                              ),
                    ),
                    if (!isMobile && subtitle?.isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.secondary(colors.playerControlMuted),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              MoviePlayerIconButton(
                icon: isMobile ? Icons.more_vert_rounded : Icons.info_outline,
                tooltip:
                    isMobile
                        ? AppLocalizations.of(context).videoPlaybackSettings
                        : AppLocalizations.of(context).videoPlaybackInfo,
                onPressed: onInfoTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
