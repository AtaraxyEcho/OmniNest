import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/profile/application/profile_controller.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_session_management_panel.dart';

void main() {
  testWidgets('重进会话管理面板时刷新会话列表', (tester) async {
    var builds = 0;
    final container = ProviderContainer.test(
      overrides: [
        userSessionsProvider.overrideWith((ref) async {
          builds += 1;
          return const [];
        }),
      ],
    );
    addTearDown(container.dispose);

    Widget host() => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(
          body: ProfileSessionManagementPanel(framed: false),
        ),
      ),
    );

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(builds, 1);

    await tester.pumpWidget(
      KeyedSubtree(key: const ValueKey('revisit'), child: host()),
    );
    await tester.pumpAndSettle();

    expect(builds, 2);
  });
}
