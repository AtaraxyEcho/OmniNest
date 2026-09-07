import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/video/presentation/widgets/movie_common_widgets.dart';

void main() {
  testWidgets('详情页返回控件具有明确标签并执行回调', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: MovieDetailBackButton(onPressed: () => tapped = true),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('movieDetailBackButton')), findsOneWidget);
    expect(find.text('返回影库'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('movieDetailBackButton')));
    expect(tapped, isTrue);
  });
}
