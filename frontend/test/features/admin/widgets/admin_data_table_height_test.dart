import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_list_components.dart';

void main() {
  testWidgets('表格内容高度与定界一致且无内部纵向滚动', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: AdminDataTable(
              columns: const [
                AdminListColumn(key: 'name', label: '名称'),
                AdminListColumn(key: 'ip', label: 'IP', minWidth: 130),
              ],
              rowCount: 3,
              rowCellsBuilder:
                  (context, index) => [
                    Text('row-$index'),
                    Text('10.0.0.$index'),
                  ],
              actionsBuilder:
                  (context, index) => [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.more_vert_rounded),
                    ),
                  ],
              showIndex: true,
              minTableWidth: 860,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // AdminDataTable 以 "表头 44 + 行数 × 行高" 定界；DataTable2 将表头与
    // 行拆成两个内部 Table（固定表头机制），二者高度之和必须恰好填满
    // 定界高度——偏差意味着出现内部纵向滚动或底部空隙。
    final bounded = find.byWidgetPredicate(
      (w) => w is SizedBox && w.height != null && w.height! > 100,
    );
    expect(bounded, findsOneWidget);
    final boundedHeight = tester.getRect(bounded).height;
    expect(boundedHeight, closeTo(44.0 + 3 * 48, 0.01));

    final totalTableHeight = find.byType(Table).evaluate().fold<double>(0, (
      sum,
      element,
    ) {
      return sum + tester.getRect(find.byWidget(element.widget)).height;
    });
    expect(
      totalTableHeight,
      closeTo(boundedHeight, 0.5),
      reason: '表头与行内容必须恰好填满定界高度，否则出现内部纵向滚动或空隙',
    );
  });
}
