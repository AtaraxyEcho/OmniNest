import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/reader/application/reader_book_provider.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/data/cached_book_handle.dart';
import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/domain/reader_item.dart';
import 'package:omninest/features/reader/presentation/pages/pdf_reader_page.dart';

/// PDF 阅读器加载链路上的异步边界（缺陷报告 M-10）。
///
/// `_load` 先取服务端进度再取缓存句柄；两次 await 之间如果用户已经退出页面，
/// 就必须在 `ref.read(pdfBookHandleProvider)` 之前返回，否则在已卸载的
/// WidgetRef 上取值会抛异常。这里让服务端详情挂起，退出后再放行。
class _MockReaderApi extends Mock implements ReaderApi {}

class _EmptyProgressStore implements ReaderLocalProgressStore {
  @override
  Future<void> clear(String itemId) async {}

  @override
  Future<Map<String, dynamic>?> load(String itemId, String chapterId) async =>
      null;

  @override
  Future<Map<String, dynamic>?> loadLatest(String itemId) async => null;

  @override
  Future<void> save({
    required String itemId,
    required double chapterProgress,
    required String mode,
    String? chapterId,
    int charOffset = 0,
    double? bookProgress,
    String? pageId,
    int? pageIndex,
    String? pageFingerprint,
    String? sourceId,
    int? sourcePageIndex,
    String? catalogKey,
    int? manifestVersion,
    double? intraPageOffset,
    DateTime? updatedAt,
  }) async {}
}

void main() {
  setUp(() => ReaderLocalProgress.init(_EmptyProgressStore()));

  testWidgets('服务端详情回来时页面已退出则不再取书籍句柄', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _MockReaderApi();
    final detailCompleter = Completer<ReaderItemDetail>();
    when(() => api.detail(any())).thenAnswer((_) => detailCompleter.future);

    final container = ProviderContainer(
      overrides: [
        readerApiProvider.overrideWithValue(api),
        // build 会 watch 句柄以维持 autoDispose 订阅；这里只保证它不真的下载。
        pdfBookHandleProvider.overrideWith(
          (ref, itemId) => Completer<CachedBookHandle>().future,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: OmniNestTheme.from(AppThemePalette.dark),
          home: const PdfReaderPage(itemId: 'item-1'),
        ),
      ),
    );
    // 让 initState 的 postFrame 加载真正走到 detail 的 await 上。
    await tester.pump();
    await tester.pump();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );
    detailCompleter.complete(_detail());
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

ReaderItemDetail _detail() => ReaderItemDetail(
  item: ReaderItem(
    id: 'item-1',
    title: 'Walden',
    itemType: 'PDF',
    updatedAt: DateTime(2026, 10, 20),
    progressPercent: 0,
  ),
);
