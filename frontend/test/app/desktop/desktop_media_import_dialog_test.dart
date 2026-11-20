import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/widgets/desktop_media_import_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<void> openDialog(
    WidgetTester tester,
    DesktopMediaImportKind kind, {
    bool allowSharedSpace = true,
  }) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopSeedOverrides(),
        child: wrapDesktop(
          Builder(
            builder:
                (context) => ElevatedButton(
                  onPressed:
                      () => showDesktopMediaImportDialog(
                        context,
                        kind: kind,
                        allowSharedSpace: allowSharedSpace,
                      ),
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('影视导入窗口给出空间选择并记住共享空间', (tester) async {
    await openDialog(tester, DesktopMediaImportKind.movies);

    expect(find.text('Add movies and shows'), findsOneWidget);
    expect(find.text('IMPORT TO'), findsOneWidget);
    expect(find.text('Personal Space'), findsOneWidget);
    expect(find.text('Shared Space'), findsOneWidget);
    expect(find.text('Match metadata after import'), findsOneWidget);

    await tester.tap(find.text('Shared Space'));
    await tester.pump();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('omninest:importSpace'), 'shared');
  });

  testWidgets('照片导入窗口不显示空间选择', (tester) async {
    await openDialog(
      tester,
      DesktopMediaImportKind.photos,
      allowSharedSpace: false,
    );

    expect(find.text('Add photos and videos'), findsOneWidget);
    expect(find.text('IMPORT TO'), findsNothing);
  });

  testWidgets('阅读导入复用同一窗口，提供图书标题与空间选择', (tester) async {
    await openDialog(tester, DesktopMediaImportKind.books);

    expect(find.text('Add books and comics'), findsOneWidget);
    expect(find.text('IMPORT TO'), findsOneWidget);
    expect(find.text('From My files'), findsOneWidget);
    expect(find.text('From this device'), findsOneWidget);
    expect(find.text('Match metadata after import'), findsNothing);
  });
}
