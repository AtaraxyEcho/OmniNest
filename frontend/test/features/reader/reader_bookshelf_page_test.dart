import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/features/reader/application/reader_bookshelf_controller.dart';
import 'package:omninest/features/reader/domain/reader_item.dart';
import 'package:omninest/features/reader/presentation/pages/reader_bookshelf_page.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_empty_state.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_shelf_row.dart';

const int _shelfCount = 200;

class _FakeBookshelfController extends ReaderBookshelfController {
  _FakeBookshelfController({this.loadedCount = _shelfCount, int? totalElements})
    : totalElements = totalElements ?? loadedCount;

  final int loadedCount;
  final int totalElements;

  @override
  Future<ReaderBookshelfState> build() async {
    return ReaderBookshelfState(
      items: [
        for (var i = 0; i < loadedCount; i++)
          ReaderItem(
            id: 'item-$i',
            title: 'Book $i',
            itemType: 'EPUB',
            addedToBookshelf: true,
            updatedAt: null,
          ),
      ],
      page: 0,
      totalElements: totalElements,
      hasMore: false,
    );
  }
}

void main() {
  testWidgets('书架列表只构建视口内的行', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
          readerBookshelfControllerProvider.overrideWith(
            _FakeBookshelfController.new,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: OmniNestTheme.dark(),
          home: const ReaderBookshelfPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final built =
        tester.widgetList<ReaderShelfRow>(find.byType(ReaderShelfRow)).length;
    expect(built, greaterThan(0));
    expect(
      built,
      lessThan(_shelfCount),
      reason: '外层若仍是页级 SingleChildScrollView，builder 惰性会失效',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('书架为空时展示空态且不报错', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
          readerBookshelfControllerProvider.overrideWith(
            () => _FakeBookshelfController(loadedCount: 0),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: OmniNestTheme.dark(),
          home: const ReaderBookshelfPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReaderShelfRow), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('书架空态卡片收束宽度并贴顶水平居中', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
          readerBookshelfControllerProvider.overrideWith(
            () => _FakeBookshelfController(loadedCount: 0),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: OmniNestTheme.dark(),
          home: const ReaderBookshelfPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cardFinder = find.byKey(ReaderEmptyState.cardKey);
    expect(cardFinder, findsOneWidget);
    final cardSize = tester.getSize(cardFinder);
    final cardRect = tester.getRect(cardFinder);
    final emptyRect = tester.getRect(find.byType(ReaderEmptyState));

    expect(
      cardSize.width,
      lessThanOrEqualTo(ReaderEmptyState.maxWidth),
      reason: '空态卡片不得随整页/SliverFillRemaining 被撑成通栏',
    );
    expect(
      cardSize.width,
      lessThan(emptyRect.width * 0.5),
      reason: '空态视觉范围应收束，而不是覆盖大半内容区',
    );
    final cardCenterX = cardRect.center.dx;
    final emptyCenterX = emptyRect.center.dx;
    expect(
      (cardCenterX - emptyCenterX).abs(),
      lessThan(8),
      reason: '空态卡片应在内容区内水平居中',
    );
    expect(
      cardRect.top - emptyRect.top,
      lessThan(48),
      reason: '空态应像书库一样贴内容区顶部，而不是在剩余高度中垂直居中',
    );
    expect(
      (cardRect.center.dy - emptyRect.center.dy).abs(),
      greaterThan(emptyRect.height * 0.15),
      reason: '空态卡片不应落在剩余高度的垂直中线附近',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('书架计数取服务端总数，不随已加载窗口变化', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
          readerBookshelfControllerProvider.overrideWith(
            () => _FakeBookshelfController(loadedCount: 3, totalElements: 200),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: OmniNestTheme.dark(),
          home: const ReaderBookshelfPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 首页只落 3 条时，头部仍须显示书架真实数量。
    expect(find.text('200'), findsOneWidget);
    expect(
      tester.widgetList<ReaderShelfRow>(find.byType(ReaderShelfRow)).length,
      equals(3),
    );
    expect(tester.takeException(), isNull);
  });
}
