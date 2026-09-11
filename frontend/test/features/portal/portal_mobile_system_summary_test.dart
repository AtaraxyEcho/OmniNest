import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_mobile_shell.dart';

void main() {
  testWidgets('系统摘要行图标统一淡染圆底，同步状态以行尾色点表达', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: OmniNestTheme.from(AppThemePalette.dark),
          home: const MobileShellScope(
            hosted: true,
            child: PortalMobileShell(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    // 在线态展示同步图标。
    final syncIcon = find.byIcon(Icons.sync_rounded);
    expect(syncIcon, findsOneWidget);
    // 图标位于 34×34 淡染圆形容器内（与其他行同权重的视觉处理）。
    final iconContainer = tester.widget<Container>(
      find.ancestor(of: syncIcon, matching: find.byType(Container)).first,
    );
    expect(iconContainer.constraints?.maxWidth, 34);
    expect(iconContainer.constraints?.maxHeight, 34);
    // 在线状态由行尾 7×7 状态色点承载，而非图标变色。
    expect(
      find.byWidgetPredicate((widget) {
        return widget is Container && widget.constraints?.maxWidth == 7;
      }),
      findsOneWidget,
    );
  });
}
