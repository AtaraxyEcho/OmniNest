import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';
import 'package:toastification/toastification.dart';
import 'package:omninest/features/reader/application/reader_data_manager.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_annotation_handler.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

class MockDataManager extends Mock implements ReaderDataManager {}

void main() {
  late MockDataManager mockDataManager;
  late ReaderViewSettings settings;
  late int notifyCount;

  setUp(() {
    mockDataManager = MockDataManager();
    settings = ReaderViewSettings();
    notifyCount = 0;
    // toastification 全局单例跨用例残留会吞掉后续条目，逐例清空。
    toastification.managers.clear();
  });

  ReaderAnnotationHandler createHandler({
    String itemId = 'item-1',
    String chapterId = 'ch-1',
  }) {
    return ReaderAnnotationHandler(
      itemId: itemId,
      chapterId: chapterId,
      dataManager: mockDataManager,
      settings: settings,
      onAnnotationsChanged: () => notifyCount++,
    );
  }

  ReaderAnnotation createAnnotation({
    String id = 'ann-1',
    String itemId = 'item-1',
    String? chapterId = 'ch-1',
    int start = 0,
    int end = 10,
    String color = '#FFEB3B',
    String note = 'test note',
  }) {
    return ReaderAnnotation(
      id: id,
      readerItemId: itemId,
      chapterId: chapterId,
      startOffset: start,
      endOffset: end,
      color: color,
      note: note,
      createdAt: DateTime(2026, 6, 9),
    );
  }

  group('ReaderAnnotationHandler', () {
    group('load', () {
      test('calls getAnnotations and updates state', () async {
        final annotations = [
          createAnnotation(id: 'ann-1', chapterId: 'ch-1'),
          createAnnotation(id: 'ann-2', chapterId: 'ch-2'),
        ];
        when(
          () => mockDataManager.loadAnnotations('item-1'),
        ).thenAnswer((_) async => annotations);

        final handler = createHandler();
        await handler.load();

        verify(() => mockDataManager.loadAnnotations('item-1')).called(1);
        expect(handler.annotations, hasLength(2));
        expect(handler.annotations.first.id, 'ann-1');
        expect(notifyCount, 1);
      });

      test('handles empty annotations list', () async {
        when(
          () => mockDataManager.loadAnnotations('item-1'),
        ).thenAnswer((_) async => []);

        final handler = createHandler();
        await handler.load();

        expect(handler.annotations, isEmpty);
        expect(notifyCount, 1);
      });

      test('does not notify when local annotation loading throws', () async {
        when(
          () => mockDataManager.loadAnnotations('item-1'),
        ).thenThrow(Exception('network error'));

        final handler = createHandler();
        await handler.load();

        expect(handler.annotations, isEmpty);
        expect(notifyCount, 0);
      });
    });

    group('delete', () {
      test('calls deleteAnnotation and reloads', () async {
        final annotation = createAnnotation(id: 'ann-5');
        when(
          () => mockDataManager.deleteAnnotation('ann-5'),
        ).thenAnswer((_) async {});
        when(
          () => mockDataManager.loadAnnotations('item-1'),
        ).thenAnswer((_) async => []);

        final handler = createHandler();
        await handler.delete(annotation);

        verify(() => mockDataManager.deleteAnnotation('ann-5')).called(1);
        verify(() => mockDataManager.loadAnnotations('item-1')).called(1);
        expect(notifyCount, 1);
      });

      test('does not crash when reloading after delete fails', () async {
        final annotation = createAnnotation();
        when(
          () => mockDataManager.deleteAnnotation(any()),
        ).thenAnswer((_) async {});
        when(
          () => mockDataManager.loadAnnotations('item-1'),
        ).thenThrow(Exception('cache unavailable'));
        final handler = createHandler();

        await handler.delete(annotation);
        expect(notifyCount, 0);
      });
    });

    group('chapterAnnotations', () {
      test('filters annotations by chapterId', () async {
        final annotations = [
          createAnnotation(id: 'ann-1', chapterId: 'ch-1'),
          createAnnotation(id: 'ann-2', chapterId: 'ch-2'),
          createAnnotation(id: 'ann-3', chapterId: 'ch-1'),
        ];
        when(
          () => mockDataManager.loadAnnotations('item-1'),
        ).thenAnswer((_) async => annotations);

        final handler = createHandler(chapterId: 'ch-1');
        await handler.load();

        expect(handler.chapterAnnotations, hasLength(2));
        expect(
          handler.chapterAnnotations.map((a) => a.id),
          containsAll(['ann-1', 'ann-3']),
        );
      });

      test('returns empty when no annotations match chapter', () async {
        final annotations = [
          createAnnotation(id: 'ann-1', chapterId: 'ch-2'),
          createAnnotation(id: 'ann-2', chapterId: 'ch-3'),
        ];
        when(
          () => mockDataManager.loadAnnotations('item-1'),
        ).thenAnswer((_) async => annotations);

        final handler = createHandler(chapterId: 'ch-1');
        await handler.load();

        expect(handler.chapterAnnotations, isEmpty);
      });

      test('returns empty before load is called', () {
        final handler = createHandler();
        expect(handler.chapterAnnotations, isEmpty);
      });

      test('uses the currently displayed chapter after navigation', () async {
        final annotations = [
          createAnnotation(id: 'ann-1', chapterId: 'ch-1'),
          createAnnotation(id: 'ann-2', chapterId: 'ch-2'),
        ];
        when(
          () => mockDataManager.loadAnnotations('item-1'),
        ).thenAnswer((_) async => annotations);

        final handler = createHandler(chapterId: 'ch-1');
        await handler.load();
        handler.updateChapter('ch-2');

        expect(handler.chapterAnnotations.single.id, 'ann-2');
      });
    });

    group('chapters field', () {
      test('can be updated to support full-book annotation mode', () async {
        when(
          () => mockDataManager.loadAnnotations('item-1'),
        ).thenAnswer((_) async => []);

        final handler = createHandler();
        expect(handler.chapters, isEmpty);

        handler.chapters = [
          const ReaderChapter(id: 'ch-1', chapterNumber: 1, title: 'Chapter 1'),
        ];
        expect(handler.chapters, hasLength(1));
      });
    });
  });
  group('highlight feedback', () {
    Widget host(ReaderAnnotationHandler handler, GlobalKey trigger) {
      return ToastificationWrapper(
        config: omniFeedbackToastConfig,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en')],
          home: Scaffold(
            body: Builder(
              key: trigger,
              builder:
                  (context) => TextButton(
                    onPressed: () => handler.highlight('选中文本', 0, 6, context),
                    child: const Text('触发高亮'),
                  ),
            ),
          ),
        ),
      );
    }

    testWidgets('保存失败时弹出错误反馈', (tester) async {
      final handler = createHandler();
      when(
        () => mockDataManager.createAnnotation(
          itemId: 'item-1',
          chapterId: 'ch-1',
          startOffset: 0,
          endOffset: 6,
          highlightText: '选中文本',
          note: null,
          color: '#FFEB3B',
        ),
      ).thenThrow(Exception('db down'));
      when(
        () => mockDataManager.loadAnnotations('item-1'),
      ).thenAnswer((_) async => []);

      final trigger = GlobalKey();
      await tester.pumpWidget(host(handler, trigger));
      await tester.tap(find.text('触发高亮'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('批注保存失败，请重试'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    });

    testWidgets('保存成功时保留既有成功反馈', (tester) async {
      final handler = createHandler();
      when(
        () => mockDataManager.createAnnotation(
          itemId: 'item-1',
          chapterId: 'ch-1',
          startOffset: 0,
          endOffset: 6,
          highlightText: '选中文本',
          note: null,
          color: '#FFEB3B',
        ),
      ).thenAnswer((_) async => createAnnotation());
      when(
        () => mockDataManager.loadAnnotations('item-1'),
      ).thenAnswer((_) async => []);

      final trigger = GlobalKey();
      await tester.pumpWidget(host(handler, trigger));
      await tester.tap(find.text('触发高亮'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('高亮已添加'), findsOneWidget);
      expect(find.text('批注保存失败，请重试'), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    });
  });
}
