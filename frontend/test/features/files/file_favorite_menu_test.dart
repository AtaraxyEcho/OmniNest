import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/presentation/widgets/file_grid.dart';
import 'package:omninest/features/files/presentation/widgets/file_list.dart';

FileNode _file(String id) {
  return FileNode(
    id: id,
    parentId: null,
    name: 'notes.txt',
    isFolder: false,
    nodeType: 'FILE',
    normalizedPath: 'notes.txt',
    sizeBytes: 1024,
    updatedAt: DateTime(2026, 9, 10),
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(500, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      theme: OmniNestTheme.light(),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('列表行菜单提供收藏项并触发回调', (tester) async {
    FileNode? toggled;
    await _pump(
      tester,
      FileList(
        files: [_file('file-1')],
        showingRecycleBin: false,
        enabled: true,
        onRename: (_) {},
        onDelete: (_) {},
        onPurge: (_) {},
        onRestore: (_) {},
        onOpen: (_) {},
        onToggleFavorite: (file) => toggled = file,
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();

    expect(toggled?.id, 'file-1');
  });

  testWidgets('收藏分区下列表菜单显示取消收藏', (tester) async {
    await _pump(
      tester,
      FileList(
        files: [_file('file-1')],
        showingRecycleBin: false,
        enabled: true,
        showingFavorites: true,
        onRename: (_) {},
        onDelete: (_) {},
        onPurge: (_) {},
        onRestore: (_) {},
        onOpen: (_) {},
        onToggleFavorite: (_) {},
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('取消收藏'), findsOneWidget);
    expect(find.text('收藏'), findsNothing);
  });

  testWidgets('网格卡片菜单提供收藏项并触发回调', (tester) async {
    FileNode? toggled;
    await _pump(
      tester,
      SizedBox(
        width: 480,
        height: 400,
        child: FileGrid(
          files: [_file('file-1')],
          showingRecycleBin: false,
          enabled: true,
          onRename: (_) {},
          onDelete: (_) {},
          onPurge: (_) {},
          onRestore: (_) {},
          onOpen: (_) {},
          onToggleFavorite: (file) => toggled = file,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();

    expect(toggled?.id, 'file-1');
  });
}
