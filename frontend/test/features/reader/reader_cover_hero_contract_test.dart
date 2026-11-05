import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/reader/domain/reader_item.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_cover_hero.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_library_cards.dart';

/// 书架封面的共享元素契约。
///
/// 书架首页的「继续阅读」横滑轨与下方主网格常同屏出现同一本书；两处都用同一个
/// Hero tag 会直接崩在 `Multiple heroes that share the same tag`。因此卡片默认
/// 不参与转场，只有主网格显式开启，且开启后的 tag 必须与详情页一致。
void main() {
  const book = ReaderItem(
    id: 'book-1',
    title: '样本书',
    itemType: 'EPUB',
    updatedAt: null,
  );

  Future<void> pumpCards(WidgetTester tester, List<Widget> cards) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: OmniNestTheme.light(),
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
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('网格卡片开启转场时产出与详情页一致的 tag', (tester) async {
    await pumpCards(tester, [
      ReaderLibraryGridCard(item: book, onTap: () {}, enableHero: true),
    ]);

    expect(find.byType(Hero), findsOneWidget);
    expect(
      tester.widget<Hero>(find.byType(Hero)).tag,
      ReaderCoverHero.tagFor('book-1'),
      reason: 'tag 必须由同一个入口生成，否则转场静默失效',
    );
  });

  testWidgets('默认不参与转场，同 id 并列也不会撞 tag', (tester) async {
    await pumpCards(tester, [
      ReaderLibraryGridCard(item: book, onTap: () {}, enableHero: true),
      ReaderLibraryGridCard(item: book, onTap: () {}),
    ]);

    // 只有开启的那张进 Hero：横滑轨同屏出现同一条目时不会触发重复 tag 断言。
    expect(find.byType(Hero), findsOneWidget);
  });

  testWidgets('关闭时不包 Hero', (tester) async {
    await pumpCards(tester, [ReaderLibraryGridCard(item: book, onTap: () {})]);

    expect(find.byType(Hero), findsNothing);
  });
}
