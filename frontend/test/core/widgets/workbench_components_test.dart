import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/widgets/workbench_navigation_bar.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';
import 'package:omninest/core/widgets/workbench_top_bar.dart';

void main() {
  testWidgets('工作台面板使用不透明主题表面并限制圆角', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.dark(),
        home: const Scaffold(
          body: WorkbenchPanel(
            key: ValueKey<String>('panel'),
            borderRadius: 32,
            child: Text('content'),
          ),
        ),
      ),
    );

    final material = tester.widget<Material>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('panel')),
        matching: find.byType(Material),
      ),
    );
    final shape = material.shape! as RoundedRectangleBorder;
    final theme = Theme.of(tester.element(find.text('content')));

    expect(material.color, theme.colorScheme.surfaceContainerLow);
    expect(material.color?.a, 1);
    expect(shape.borderRadius, BorderRadius.circular(8));
  });

  testWidgets('工作台面板为列表项提供可见的 Material 表面', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.dark(),
        home: Scaffold(
          body: WorkbenchPanel(
            child: ListTile(
              title: const Text('action'),
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('action'));
    await tester.pump();

    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('工作台顶部栏使用不透明表面', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.light(),
        home: const Scaffold(
          body: WorkbenchTopBar(
            key: ValueKey<String>('top-bar'),
            child: Text('toolbar'),
          ),
        ),
      ),
    );

    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: find.byKey(const ValueKey<String>('top-bar')),
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;
    final theme = Theme.of(tester.element(find.text('toolbar')));

    expect(decoration.color, theme.colorScheme.surface);
    expect(decoration.color?.a, 1);
  });

  testWidgets('工作台底部导航转发目标索引', (tester) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.light(),
        home: Scaffold(
          bottomNavigationBar: WorkbenchNavigationBar(
            currentIndex: 0,
            onTap: (index) => selected = index,
            items: const <WorkbenchNavigationItem>[
              WorkbenchNavigationItem(
                icon: Icons.folder_outlined,
                selectedIcon: Icons.folder,
                label: 'Files',
              ),
              WorkbenchNavigationItem(
                icon: Icons.history_outlined,
                selectedIcon: Icons.history,
                label: 'Recent',
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Recent'));
    await tester.pumpAndSettle();

    expect(selected, 1);
  });
}
