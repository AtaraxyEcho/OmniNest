// 片尾自动连播提示卡回归：倒计时文案按秒数变化，两个动作各自只触发一次回调。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_autoplay_notice.dart';

void main() {
  testWidgets('倒计时与下一集标题都渲染出来', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.from(AppThemePalette.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Stack(
            children: [
              MoviePlayerAutoplayNotice(
                episodeTitle: '第 3 集 · 深眠',
                secondsLeft: 4,
                onPlayNow: () {},
                onCancel: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('将在 4 秒后播放下一集'), findsOneWidget);
    expect(find.text('第 3 集 · 深眠'), findsOneWidget);
    expect(find.text('立即播放'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('倒计时变化只改文案不改布局', (tester) async {
    Widget wrap(int secondsLeft) => MaterialApp(
      theme: OmniNestTheme.from(AppThemePalette.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: Stack(
          children: [
            MoviePlayerAutoplayNotice(
              episodeTitle: 'Episode 3',
              secondsLeft: secondsLeft,
              onPlayNow: () {},
              onCancel: () {},
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(wrap(5));
    expect(find.text('Next episode in 5s'), findsOneWidget);

    await tester.pumpWidget(wrap(1));
    expect(find.text('Next episode in 1s'), findsOneWidget);
    expect(find.text('Next episode in 5s'), findsNothing);
  });

  testWidgets('两个按钮分别触发立即播放与取消', (tester) async {
    var played = 0;
    var cancelled = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.from(AppThemePalette.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Stack(
            children: [
              MoviePlayerAutoplayNotice(
                episodeTitle: '第 3 集 · 深眠',
                secondsLeft: 3,
                onPlayNow: () => played++,
                onCancel: () => cancelled++,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('立即播放'));
    await tester.tap(find.text('取消'));

    expect(played, 1);
    expect(cancelled, 1);
  });
}
