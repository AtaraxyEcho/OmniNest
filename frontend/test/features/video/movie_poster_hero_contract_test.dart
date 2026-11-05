import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_poster_card.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_status.dart';

/// 共享元素转场的开关契约。
///
/// 影视中心同一路由里，主网格与「继续观看」横滑轨经常出现同一条目；两处都用
/// 同一个 Hero tag 会直接崩在 `Multiple heroes that share the same tag`。
/// 因此只有网格卡片允许开启，且 tag 必须与详情页封面一致。
void main() {
  const data = MovieRedesignCardData(
    id: 'movie-1',
    title: '海报标题',
    year: '2024',
    status: MovieRedesignStatus.matched,
  );

  Future<void> pumpCards(WidgetTester tester, List<Widget> cards) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          // 卡片内部用 Expanded 撑开标题区，必须给有限高度。
          body: Row(
            children: [
              for (final card in cards)
                SizedBox(width: 180, height: 320, child: card),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('关闭转场的卡片不产生 Hero，同 id 并列也不会重复 tag', (tester) async {
    await pumpCards(tester, [
      const MovieRedesignPosterCard(data: data, enableHero: true),
      const MovieRedesignPosterCard(data: data),
    ]);

    // 只有一个 Hero：把开关关掉的那张不参与，重复 tag 的断言不会被触发。
    expect(find.byType(Hero), findsOneWidget);
    expect(
      tester.widget<Hero>(find.byType(Hero)).tag,
      'movie-poster-movie-1',
      reason: 'tag 必须与详情页封面一致，否则转场不会发生',
    );
  });

  testWidgets('默认关闭转场，列表外场景不会无意间造出 Hero', (tester) async {
    await pumpCards(tester, const [MovieRedesignPosterCard(data: data)]);

    expect(find.byType(Hero), findsNothing);
  });
}
