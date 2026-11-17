import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/appearance/application/composed_scaler.dart';
import 'package:omninest/app/appearance/application/font_scale_scope.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_chapter_end_card.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 摘要：稿子的章末两块——发丝线行写真实位次，下一章卡只在还有下一章时出现。
///
/// 另有两条只跟高度有关的判据：渲染高度必须**等于**下发到懒建列表的确定高度
/// （`itemExtentBuilder` 给的是紧约束，短一格就是 RenderFlex overflow，长一格就是
/// 列表按虚高给出的一段空页），且必须随环境文字缩放同步放大。相等靠卡片把每行钉进
/// 自己的行盒取得：1.25 缩放的排版值是 17.5，平台把行盒取整到哪一格因字面而异，
/// 而 flutter_test 把每一个字族都解析成同一张 1.4em 测试字面（打包字体用
/// `loadFontFromList` 载入后行高照旧按测试字面给值），本文件量不出真机那一格——
/// 所以卡片规定行盒，不预测它。
void main() {
  final settings = ReaderViewSettings();

  /// 高度判据里用到的缩放档：1 是默认，1.25/1.5 是 Android 大字体，1.6 是应用字体档
  /// 与系统档叠加后的上限（`ComposedScaler.maxScale`），3 是无障碍上限——390px 宽在
  /// 这一档会把发丝线行的小字顶出行外，只有把它排进档位才会被断到。
  const scales = <double>[1, 1.25, 1.5, 1.6, 3];

  Widget host(Widget child, {required double textScale, double? tightHeight}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: Builder(
          builder:
              (context) => MediaQuery(
                // copyWith 保留尺寸与内边距：裸 MediaQueryData 会把视口清成零尺寸。
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 390,
                    height: tightHeight,
                    child: child,
                  ),
                ),
              ),
        ),
      ),
    );
  }

  Future<AppLocalizations> pump(
    WidgetTester tester, {
    String? nextChapterTitle,
    VoidCallback? onNextChapter,
    double textScale = 1,
    double? tightHeight,
    double devicePixelRatio = 1,
  }) async {
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(
        ReaderChapterEndCard(
          settings: settings,
          chapterLabel: '第 3/12 章 · 47%',
          nextChapterTitle: nextChapterTitle,
          onNextChapter: onNextChapter,
        ),
        textScale: textScale,
        tightHeight: tightHeight,
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(
      tester.element(find.byType(ReaderChapterEndCard)),
    );
  }

  testWidgets('有下一章时给出可点卡片', (tester) async {
    var tapped = 0;
    final l10n = await pump(
      tester,
      nextChapterTitle: '第七章 火焰山',
      onNextChapter: () => tapped++,
    );

    expect(find.text('第 3/12 章 · 47%'), findsOneWidget);
    expect(find.text(l10n.readerNextChapter), findsOneWidget);
    expect(find.text('第七章 火焰山'), findsOneWidget);

    await tester.tap(find.text('第七章 火焰山'));
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });

  testWidgets('末章只剩发丝线行，不摆空卡', (tester) async {
    final l10n = await pump(tester);

    expect(find.text('第 3/12 章 · 47%'), findsOneWidget);
    expect(find.text(l10n.readerNextChapter), findsNothing);
    // 稿子的两块几何：发丝线行 52 + 一行小字 + 26，下一章卡 min-height 76。
    expect(ReaderChapterEndCard.dividerHeightFor(TextScaler.linear(1)), 92.0);
    expect(ReaderChapterEndCard.nextCardHeightFor(TextScaler.linear(1)), 76.0);
    expect(
      ReaderChapterEndCard.heightFor(
        hasNextChapter: false,
        scaler: TextScaler.linear(1),
      ),
      ReaderChapterEndCard.dividerHeightFor(TextScaler.linear(1)),
    );
    expect(
      ReaderChapterEndCard.heightFor(
        hasNextChapter: true,
        scaler: TextScaler.linear(1),
      ),
      ReaderChapterEndCard.dividerHeightFor(TextScaler.linear(1)) +
          ReaderChapterEndCard.nextCardHeightFor(TextScaler.linear(1)),
    );
  });

  for (final scale in scales) {
    testWidgets('缩放到 $scale：渲染高度与确定高度一格不差且紧约束不溢出', (tester) async {
      for (final title in <String?>['第七章 火焰山', null]) {
        // 先拿松约束量真实渲染高度，再按 heightFor 给的紧约束摆一次。
        // dpr 也扫：真机是 2-3.5。
        for (final dpr in const <double>[1, 2, 3, 3.5]) {
          await pump(
            tester,
            nextChapterTitle: title,
            textScale: scale,
            devicePixelRatio: dpr,
          );
          final rendered =
              tester.getSize(find.byType(ReaderChapterEndCard)).height;
          final extent = ReaderChapterEndCard.heightFor(
            hasNextChapter: title != null,
            scaler: TextScaler.linear(scale),
          );
          // 行盒由卡片自己钉死，两边必须相等：多留一格是列表按虚高给出的空页，
          // 少一格就是真机上那条 `RenderFlex overflowed by 1.00 pixels`。
          expect(
            rendered,
            extent,
            reason: '$title/$scale dpr=$dpr：渲染 $rendered 对不上确定高度 $extent',
          );

          await pump(
            tester,
            nextChapterTitle: title,
            textScale: scale,
            tightHeight: extent,
            devicePixelRatio: dpr,
          );
          expect(
            tester.takeException(),
            isNull,
            reason:
                'heightFor 短于渲染高度时，itemExtentBuilder 的紧约束会报 overflow'
                '（dpr=$dpr）',
          );
        }
      }
    });
  }

  // 章末卡渲染在内容层（只保留系统缩放）里，条目高度必须按同一层推算。
  // 按页面环境值（系统×应用字体档位）算，档位低于标准时就比渲染矮整整一行，
  // 而滚动列表下发的是紧约束。
  for (final system in <double>[1.0, 1.15]) {
    testWidgets('应用档位紧凑时仍按内容层缩放给高度（系统 $system）', (tester) async {
      final composed = ComposedScaler(TextScaler.linear(system), 0.9);
      final systemOnly = ComposedScaler(TextScaler.linear(system), 1);
      late double extent;
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder:
                (pageContext) => MediaQuery(
                  data: MediaQuery.of(
                    pageContext,
                  ).copyWith(textScaler: composed),
                  child: FontScaleScope(
                    systemScaler: systemOnly,
                    child: Builder(
                      builder: (scaleContext) {
                        // 与阅读页同位：条目高度在剥离应用档位之前算。
                        extent = ReaderChapterEndCard.heightFor(
                          hasNextChapter: true,
                          scaler: FontScaleScope.systemScalerOf(scaleContext),
                        );
                        return FontScaleScope.withSystemScaleOnly(
                          context: scaleContext,
                          child: Scaffold(
                            body: Align(
                              alignment: Alignment.topLeft,
                              child: SizedBox(
                                width: 390,
                                height: extent,
                                child: ReaderChapterEndCard(
                                  settings: settings,
                                  chapterLabel: '第 3/12 章 · 47%',
                                  nextChapterTitle: '第七章 火焰山',
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: '内容层按系统缩放渲染，条目高度按页面环境值算会短 1px',
      );
      expect(tester.getSize(find.byType(ReaderChapterEndCard)).height, extent);
      // 反证：把应用档位算进条目高度就会短一格，卡片按内容层缩放渲染。
      expect(
        ReaderChapterEndCard.heightFor(hasNextChapter: true, scaler: composed),
        lessThan(extent),
      );
    });
  }
}
