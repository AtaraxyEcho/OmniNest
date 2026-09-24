import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/domain/reader_dashboard.dart';
import 'package:omninest/features/reader/domain/reader_item.dart';
import 'package:omninest/features/reader/presentation/pages/reader_bookshelf_page.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_shelf_row.dart';

const int _shelfCount = 200;

class _FakeReaderCenterController extends ReaderCenterController {
  @override
  Future<ReaderCenterState> build() async {
    return ReaderCenterState(
      dashboard: ReaderDashboard.empty(),
      items: [
        for (var i = 0; i < _shelfCount; i++)
          ReaderItem(
            id: 'item-$i',
            title: 'Book $i',
            itemType: 'EPUB',
            addedToBookshelf: true,
            updatedAt: null,
          ),
      ],
      searchQuery: '',
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
          readerCenterControllerProvider.overrideWith(
            _FakeReaderCenterController.new,
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
          readerCenterControllerProvider.overrideWith(
            () => _EmptyReaderCenterController(),
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
}

class _EmptyReaderCenterController extends ReaderCenterController {
  @override
  Future<ReaderCenterState> build() async {
    return ReaderCenterState(
      dashboard: ReaderDashboard.empty(),
      items: const [],
      searchQuery: '',
    );
  }
}
