import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/mobile_sheet_semantics.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';

void main() {
  testWidgets('自绘底部面板经包装后拿到 dialog role', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MobileShellScope(
              hosted: true,
              child: Builder(
                builder:
                    (context) => TextButton(
                      onPressed:
                          () => showMobileConfirmSheet(
                            context,
                            title: 'Delete file',
                            message: 'Body',
                          ),
                      child: const Text('open'),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(MobileSheetSemantics),
      ),
      findsOneWidget,
    );
    final wrappers = tester.widgetList<Semantics>(
      find.ancestor(
        of: find.text('Delete file'),
        matching: find.byType(Semantics),
      ),
    );
    expect(
      wrappers.map((widget) => widget.properties.role),
      contains(SemanticsRole.dialog),
      reason: '面板不经过 WorkstationDialogFrame，role 由 MobileSheetSemantics 补齐',
    );
  });
}
