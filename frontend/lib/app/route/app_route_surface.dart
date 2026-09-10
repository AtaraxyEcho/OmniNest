import 'package:flutter/material.dart';
import 'package:omninest/app/theme/mobile_app_theme.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_scene_scope.dart';

class AppRouteSurface extends StatelessWidget {
  const AppRouteSurface({
    required this.owner,
    required this.policy,
    required this.child,
    super.key,
  });

  final String owner;
  final AppBackdropPolicy policy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final useMobileTheme =
        isMobilePlatform ||
        ResponsiveBreakpoints.isCompact(MediaQuery.sizeOf(context).width);
    Widget content = Builder(
      builder:
          (context) => ColoredBox(
            color:
                policy.visible
                    ? Colors.transparent
                    : Theme.of(context).colorScheme.surface,
            child: child,
          ),
    );
    if (useMobileTheme) {
      content = Theme(
        data: MobileAppTheme.resolve(Theme.of(context)),
        child: content,
      );
    }
    return AppBackdropSceneScope(owner: owner, policy: policy, child: content);
  }
}
