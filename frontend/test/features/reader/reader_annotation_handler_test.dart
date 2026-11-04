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

  /// 提供一个可读 localizations 的 BuildContext：批注反馈要在挂载上下文上弹提示。
  Future<BuildContext> hostedContext(WidgetTester tester) async {
    BuildContext? captured;
    await tester.pumpWidget(
      ToastificationWrapper(
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
              builder: (context) {
                captured = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    return captured!;
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
      testWidgets('stages delete, updates memory, and commits after TTL', (
        tester,
      ) async {
        final annotation = createAnnotation(id: 'ann-5', note: '');
        when(
          () => mockDataManager.loadAnnotations('item-1'),
        ).thenAnswer((_) async => [annotation]);
        when(
          () => mockDataManager.deleteAnnotation('ann-5'),
        ).thenAnswer((_) async {});

        final handler = createHandler();
        final context = await hostedContext(tester);
        await handler.load();
        final loadCount = notifyCount;
        await handler.delete(annotation, context);

        expect(handler.annotations, isEmpty);
        expect(notifyCount, loadCount + 1);
        verifyNever(() => mockDataManager.deleteAnnotation('ann-5'));

        await tester.pump(const Duration(seconds: 7));
        verify(() => mockDataManager.deleteAnnotation('ann-5')).called(1);
        verify(() => mockDataManager.loadAnnotations('item-1')).called(1);
      });

      testWidgets('undo restores the annotation without touching storage', (
        tester,
      ) async {
        final annotation = createAnnotation(note: '');
        when(
          () => mockDataManager.loadAnnotations('item-1'),
        ).thenAnswer((_) async => [annotation]);
        when(
          () => mockDataManager.deleteAnnotation(any()),
        ).thenAnswer((_) async {});
        final handler = createHandler();
        final context = await hostedContext(tester);
        await handler.load();
        await handler.delete(annotation, context);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(handler.annotations, isEmpty);
        expect(find.text('撤销'), findsOneWidget);

        await tester.tap(find.text('撤销'));
        await tester.pump();
        expect(handler.annotations.single.id, annotation.id);

        await tester.pump(const Duration(seconds: 7));
        verifyNever(() => mockDataManager.deleteAnnotation(any()));
      });

      testWidgets('含笔记批注删除先确认，取消不删除', (tester) async {
        final annotation = createAnnotation(id: 'ann-note', note: '长笔记');
        when(
          () => mockDataManager.loadAnnotations('item-1'),
        ).thenAnswer((_) async => [annotation]);
        when(
          () => mockDataManager.deleteAnnotation(any()),
        ).thenAnswer((_) async {});
        final handler = createHandler();
        final context = await hostedContext(tester);
        await handler.load();

        final future = handler.delete(annotation, context);
        await tester.pumpAndSettle();
        expect(find.text('该批注包含笔记，确认删除？'), findsOneWidget);

        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        await future;

        expect(handler.annotations.single.id, 'ann-note');
        verifyNever(() => mockDataManager.deleteAnnotation(any()));
      });

      testWidgets('删除提交失败要恢复批注并弹出反馈', (tester) async {
        final annotation = createAnnotation(id: 'ann-7', note: '');
        when(
          () => mockDataManager.loadAnnotations('item-1'),
        ).thenAnswer((_) async => [annotation]);
        when(
          () => mockDataManager.deleteAnnotation('ann-7'),
        ).thenThrow(Exception('db down'));
        final handler = createHandler();
        final context = await hostedContext(tester);
        await handler.load();

        await handler.delete(annotation, context);
        expect(handler.annotations, isEmpty);

        await tester.pump(const Duration(seconds: 7));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.text('批注删除失败，请重试'), findsOneWidget);
        expect(handler.annotations.single.id, 'ann-7');
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
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

    testWidgets('重叠高亮先创建后删除，并保留旧批注笔记', (tester) async {
      final handler = createHandler();
      final old = createAnnotation(
        id: 'old',
        chapterId: 'ch-1',
        start: 0,
        end: 10,
        note: '旧笔记',
      );
      when(
        () => mockDataManager.loadAnnotations('item-1'),
      ).thenAnswer((_) async => [old]);
      await handler.load();

      final events = <String>[];
      when(
        () => mockDataManager.createAnnotation(
          itemId: 'item-1',
          chapterId: 'ch-1',
          startOffset: 0,
          endOffset: 6,
          highlightText: '选中文本',
          note: '旧笔记',
          color: '#FFEB3B',
        ),
      ).thenAnswer((_) async {
        events.add('create');
        return createAnnotation(
          id: 'new',
          chapterId: 'ch-1',
          start: 0,
          end: 6,
          note: '旧笔记',
        );
      });
      when(() => mockDataManager.deleteAnnotation('old')).thenAnswer((_) async {
        events.add('delete');
      });

      final trigger = GlobalKey();
      await tester.pumpWidget(host(handler, trigger));
      await tester.tap(find.text('触发高亮'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(events, ['create', 'delete']);
      expect(handler.annotations.single.id, 'new');
      expect(handler.annotations.single.note, '旧笔记');
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

  testWidgets('选中的高亮色作为本次与后续默认色', (tester) async {
    final handler = createHandler();
    final context = await hostedContext(tester);
    when(
      () => mockDataManager.createAnnotation(
        itemId: 'item-1',
        chapterId: 'ch-1',
        startOffset: 0,
        endOffset: 2,
        highlightText: '甲',
        note: null,
        color: '#4CAF50',
      ),
    ).thenAnswer(
      (_) async => createAnnotation(
        id: 'green',
        chapterId: 'ch-1',
        start: 0,
        end: 2,
        color: '#4CAF50',
        note: '',
      ),
    );
    when(
      () => mockDataManager.createAnnotation(
        itemId: 'item-1',
        chapterId: 'ch-1',
        startOffset: 3,
        endOffset: 4,
        highlightText: '乙',
        note: null,
        color: '#4CAF50',
      ),
    ).thenAnswer(
      (_) async => createAnnotation(
        id: 'green-2',
        chapterId: 'ch-1',
        start: 3,
        end: 4,
        color: '#4CAF50',
        note: '',
      ),
    );

    await handler.highlight('甲', 0, 2, context, color: '#4CAF50');
    await handler.highlight('乙', 3, 4, context);

    verify(
      () => mockDataManager.createAnnotation(
        itemId: 'item-1',
        chapterId: 'ch-1',
        startOffset: 3,
        endOffset: 4,
        highlightText: '乙',
        note: null,
        color: '#4CAF50',
      ),
    ).called(1);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  group('批注面板', () {
    Widget panelHost(Widget Function(BuildContext context) build) {
      return MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: Scaffold(
          body: SizedBox(height: 600, child: Builder(builder: build)),
        ),
      );
    }

    ReaderAnnotationHandler handlerWithSelect(
      List<String> jumps, {
      bool edit = true,
    }) {
      return ReaderAnnotationHandler(
        itemId: 'item-1',
        chapterId: 'ch-1',
        dataManager: mockDataManager,
        settings: settings,
        onAnnotationsChanged: () {},
        onSelectAnnotation:
            edit
                ? (chapterId, startOffset) =>
                    jumps.add('$chapterId:$startOffset')
                : null,
      );
    }

    testWidgets('点按卡片回调章节与章内偏移', (tester) async {
      final jumps = <String>[];
      final handler = handlerWithSelect(jumps);
      when(() => mockDataManager.loadAnnotations('item-1')).thenAnswer(
        (_) async => [createAnnotation(chapterId: 'ch-1', start: 300)],
      );
      await handler.load();

      await tester.pumpWidget(panelHost(handler.buildPanel));
      await tester.tap(find.text('test note'));
      await tester.pump();

      expect(jumps, ['ch-1:300']);
    });

    testWidgets('纯高亮也提供编辑入口，可补加备注', (tester) async {
      final jumps = <String>[];
      final handler = handlerWithSelect(jumps);
      when(() => mockDataManager.loadAnnotations('item-1')).thenAnswer(
        (_) async => [createAnnotation(chapterId: 'ch-1', note: '', start: 12)],
      );
      await handler.load();

      await tester.pumpWidget(panelHost(handler.buildPanel));

      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    });

    testWidgets('清空备注后确认按空串提交', (tester) async {
      final handler = handlerWithSelect(<String>[]);
      when(
        () => mockDataManager.loadAnnotations('item-1'),
      ).thenAnswer((_) async => [createAnnotation(chapterId: 'ch-1')]);
      await handler.load();
      when(
        () => mockDataManager.updateAnnotation(
          annotationId: 'ann-1',
          note: any(named: 'note'),
          color: any(named: 'color'),
        ),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(panelHost(handler.buildPanel));
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '',
      );
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      verify(
        () => mockDataManager.updateAnnotation(
          annotationId: 'ann-1',
          note: '',
          color: '#FFEB3B',
        ),
      ).called(1);
    });
  });
}
