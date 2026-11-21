import 'package:material_ui/material_ui.dart';

import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/app/desktop/desktop_shell.dart' show DesktopFormSwitch;
import 'package:omninest/app/route/boot_page.dart';
import 'package:omninest/core/widgets/brand_logo.dart';

/// 启动页（样例 `Auth.tsx` 的 `Splash`）：品牌标 + 衬线字标 + 一条走线。
///
/// 真实启动只在这一屏停留到会话检查完成，但「冷启动看到品牌」是样例的
/// 第一印象，不该被一个裸转圈替代。
class DesktopSplashPage extends StatefulWidget {
  const DesktopSplashPage({super.key});

  @override
  State<DesktopSplashPage> createState() => _DesktopSplashPageState();
}

class _DesktopSplashPageState extends State<DesktopSplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _line = AnimationController(
    vsync: this,
    duration: DesktopMotion.slow,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: skin.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandLogo(size: 72, radius: 20),
            const SizedBox(height: 22),
            Text(
              AppLocalizations.of(context).appName,
              // 样例 `.sp-mark h1 { font-size: 44px }`：固定值，不随窗口缩放。
              style: DesktopType.splashTitle(skin.text),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 140,
              height: 2,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child:
                    reduceMotion
                        ? ColoredBox(color: skin.accent)
                        : AnimatedBuilder(
                          animation: _line,
                          builder:
                              (context, _) => LinearProgressIndicator(
                                value: 0.15 + _line.value * 0.7,
                                backgroundColor: skin.raise,
                                color: skin.accent,
                                minHeight: 2,
                              ),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 启动分支：桌面形态给品牌启动页，移动形态保留原转圈页。
class DesktopBootSwitch extends StatelessWidget {
  const DesktopBootSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return const DesktopFormSwitch(
      desktop: DesktopSplashPage(),
      mobile: BootPage(),
    );
  }
}
