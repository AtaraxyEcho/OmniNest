import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_empty_state.dart';

void main() {
  testWidgets('空态只渲染文案，不提供操作按钮', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: MovieRedesignEmptyState(
            icon: Icons.play_circle_outline_rounded,
            title: '这里还没有媒体条目。',
            subtitle: '稍后再来看看。',
          ),
        ),
      ),
    );
    expect(find.text('这里还没有媒体条目。'), findsOneWidget);
    expect(find.text('稍后再来看看。'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('空态文案收束宽度且水平居中', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: MovieRedesignEmptyState(icon: Icons.movie_outlined, title: '空'),
        ),
      ),
    );

    final contentFinder = find.byKey(MovieRedesignEmptyState.contentKey);
    expect(contentFinder, findsOneWidget);
    final contentSize = tester.getSize(contentFinder);
    final contentRect = tester.getRect(contentFinder);
    final bodyRect = tester.getRect(find.byType(Scaffold));

    expect(
      contentSize.width,
      lessThanOrEqualTo(MovieRedesignEmptyState.maxWidth),
    );
    expect(
      (contentRect.center.dx - bodyRect.center.dx).abs(),
      lessThan(8),
      reason: '空态内容应在页面内容区水平居中',
    );
    expect(tester.takeException(), isNull);
  });
}
