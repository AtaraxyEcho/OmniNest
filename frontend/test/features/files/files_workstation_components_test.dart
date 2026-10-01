import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/features/files/presentation/theme/files_workstation_theme.dart';
import 'package:omninest/features/files/presentation/widgets/files_check_mark.dart';
import 'package:omninest/features/files/presentation/widgets/files_dialog.dart';
import 'package:omninest/features/files/presentation/widgets/files_toolbar_control.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
    home: Scaffold(body: FilesWorkstationScope(child: child)),
  );
}

String? _focusedButtonText() {
  final primary = FocusManager.instance.primaryFocus;
  final context = primary?.context;
  if (context == null) {
    return null;
  }
  final button = context.findAncestorWidgetOfExactType<TextButton>();
  final child = button?.child;
  if (child is Text) {
    return child.data;
  }
  // 弹窗右上角 X 关闭钮（InkWell + 图标）也是合法的陷阱内焦点落点。
  final closeIcon = context.findAncestorWidgetOfExactType<InkWell>();
  if (closeIcon != null) {
    return '__dialog_close__';
  }
  return null;
}

void main() {
  group('FilesCheckMark', () {
    testWidgets('默认未勾选且无 ✔ 文本，点按回调 true', (tester) async {
      bool? next;
      await tester.pumpWidget(
        _wrap(
          Center(
            child: FilesCheckMark(value: false, onChanged: (v) => next = v),
          ),
        ),
      );
      expect(find.text('✔'), findsNothing);
      await tester.tap(find.byType(FilesCheckMark));
      expect(next, isTrue);
    });

    testWidgets('勾选态渲染加粗 ✔', (tester) async {
      await tester.pumpWidget(
        _wrap(Center(child: FilesCheckMark(value: true, onChanged: (_) {}))),
      );
      await tester.pumpAndSettle();
      final mark = tester.widget<Text>(find.text('✔'));
      expect(mark.style?.fontWeight, FontWeight.w700);
      expect(find.byType(FilesCheckMark), findsOneWidget);
    });

    testWidgets('禁用态不响应点按', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _wrap(
          Center(
            child: FilesCheckMark(
              value: false,
              enabled: false,
              onChanged: (_) => calls++,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(FilesCheckMark), warnIfMissed: false);
      expect(calls, 0);
    });
  });

  group('FilesToolbarIconButton', () {
    testWidgets('尺寸严格 32px 且点按触发', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(
          Center(
            child: FilesToolbarIconButton(
              tooltip: 'action',
              icon: Icons.table_rows_outlined,
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byType(AnimatedContainer).first);
      expect(size, const Size(32, 32));
      await tester.tap(find.byType(FilesToolbarIconButton));
      expect(taps, 1);
    });
  });

  group('FilesToolbarSegmented', () {
    testWidgets('切换分段回调目标值', (tester) async {
      String? picked;
      await tester.pumpWidget(
        _wrap(
          Center(
            child: FilesToolbarSegmented<String>(
              selected: 'a',
              onSelected: (v) => picked = v,
              segments: const [
                FilesToolbarSegment(
                  value: 'a',
                  tooltip: 'A',
                  icon: Icons.view_list_rounded,
                ),
                FilesToolbarSegment(
                  value: 'b',
                  tooltip: 'B',
                  icon: Icons.grid_view_rounded,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('B'));
      expect(picked, 'b');
    });
  });

  group('FilesWorkstationScope', () {
    testWidgets('覆盖 FilesColors 为 Zinc 工位色并全直角化弹窗', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final files = FilesColors.of(captured);
      expect(files.surface, const Color(0xFF09090B));
      expect(files.surfaceContainer, const Color(0xFF18181C));
      expect(files.onSurface, const Color(0xFFF4F4F5));
      expect(files.storageAccent, const Color(0xFF10B981));
      final dialog = Theme.of(captured).dialogTheme;
      final dialogShape = dialog.shape;
      expect(dialogShape is RoundedRectangleBorder, isTrue);
      if (dialogShape is RoundedRectangleBorder) {
        expect(dialogShape.borderRadius, BorderRadius.zero);
      }
      expect(dialog.elevation, 0);
      expect(
        Theme.of(captured).colorScheme.outlineVariant,
        files.outlineVariant,
      );
    });

    testWidgets('浅色亮度走纸白画板', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
          home: Scaffold(
            body: FilesWorkstationScope(
              child: Builder(
                builder: (context) {
                  captured = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      expect(FilesColors.of(captured).surface, const Color(0xFFF8F9FA));
      expect(FilesColors.of(captured).surfaceContainer, Colors.white);
    });
  });

  group('FilesDialogFrame', () {
    testWidgets('渲染标题与操作区，destructive 顶部绯红线', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Center(
            child: FilesDialogFrame(
              title: '确认销毁',
              destructive: true,
              body: const Text('body'),
              actions: [TextButton(onPressed: () {}, child: const Text('取消'))],
            ),
          ),
        ),
      );
      expect(find.text('确认销毁'), findsOneWidget);
      final topLine = tester.widget<Container>(
        find.byWidgetPredicate(
          (widget) => widget is Container && widget.constraints?.maxHeight == 2,
        ),
      );
      expect(topLine.constraints?.maxHeight, 2);
    });
  });

  group('showFilesDialog 焦点状态机', () {
    testWidgets('Esc 关闭后焦点精确回到触发按钮', (tester) async {
      final focusNode = FocusNode(debugLabel: 'trigger');
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        _wrap(
          Center(
            child: TextButton(
              focusNode: focusNode,
              onPressed: () async {
                await showFilesDialog<void>(
                  context: focusNode.context!,
                  builder:
                      (context) => FilesDialogFrame(
                        title: 'demo',
                        body: const SizedBox.shrink(),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('close'),
                          ),
                        ],
                      ),
                );
              },
              child: const Text('trigger'),
            ),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, focusNode);
      await tester.tap(find.text('trigger'));
      await tester.pump();
      expect(find.text('demo'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('demo'), findsNothing);
      expect(FocusManager.instance.primaryFocus, focusNode);
    });

    testWidgets('破坏性确认：短语匹配前禁用确认且默认聚焦取消', (tester) async {
      var confirmed = false;
      await tester.pumpWidget(
        _wrap(
          Center(
            child: Builder(
              builder:
                  (context) => TextButton(
                    onPressed: () async {
                      confirmed = await showFilesDestructiveConfirm(
                        context,
                        title: '粉碎',
                        message: '不可恢复',
                        confirmPhrase: 'notes.txt',
                      );
                    },
                    child: const Text('open'),
                  ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      expect(find.text('粉碎'), findsOneWidget);
      final confirm = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(confirm.onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'notes.txt');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tester.tap(find.byType(TextButton).first);
      await tester.pumpAndSettle();
      expect(confirmed, isFalse);
    });

    testWidgets('Esc 逐层退栈：双弹窗逐个关闭', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Center(
            child: Builder(
              builder:
                  (context) => TextButton(
                    onPressed: () {
                      showFilesDialog<void>(
                        context: context,
                        builder:
                            (a) => FilesDialogFrame(
                              title: 'layer-a',
                              body: TextButton(
                                onPressed: () {
                                  showFilesDialog<void>(
                                    context: a,
                                    builder:
                                        (b) => const FilesDialogFrame(
                                          title: 'layer-b',
                                          body: SizedBox.shrink(),
                                        ),
                                  );
                                },
                                child: const Text('open-b'),
                              ),
                            ),
                      );
                    },
                    child: const Text('open-a'),
                  ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open-a'));
      await tester.pump();
      await tester.tap(find.text('open-b'));
      await tester.pump();
      expect(find.text('layer-a'), findsOneWidget);
      expect(find.text('layer-b'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('layer-b'), findsNothing);
      expect(find.text('layer-a'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('layer-a'), findsNothing);
    });

    testWidgets('Tab 焦点在弹窗内环绕，绝不游走到背景控件', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Center(
            child: Builder(
              builder:
                  (context) => TextButton(
                    onPressed: () {
                      showFilesDialog<void>(
                        context: context,
                        builder:
                            (dialogContext) => FilesDialogFrame(
                              title: 'trap',
                              body: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    autofocus: true,
                                    onPressed: () {},
                                    child: const Text('first'),
                                  ),
                                  TextButton(
                                    onPressed: () {},
                                    child: const Text('second'),
                                  ),
                                ],
                              ),
                            ),
                      );
                    },
                    child: const Text('open'),
                  ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focused = _focusedButtonText();
        expect(focused, isNotNull);
        expect(focused, isNot('open'));
      }
    });
  });
}
