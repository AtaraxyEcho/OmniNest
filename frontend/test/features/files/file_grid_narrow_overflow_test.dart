import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/presentation/widgets/file_grid.dart';

/// 卡片行内的固定控件（Checkbox 48 + 缩略图 42 + 菜单钮 48）在手机两列卡片里
/// 超过内容宽度，多选态会在 RenderFlex 溢出。
Future<void> _pumpGrid(
  WidgetTester tester, {
  required Size surface,
  required bool selectionActive,
  double textScale = 1.0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = surface;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: OmniNestTheme.from(AppThemePalette.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: FileGrid(
            files: _files,
            showingRecycleBin: false,
            enabled: true,
            selectionActive: selectionActive,
            selectedFileIds: const {'file-1'},
            onRename: (_) {},
            onDelete: (_) {},
            onPurge: (_) {},
            onRestore: (_) {},
            onOpen: (_) {},
            onToggleSelection: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('手机宽度常态网格不溢出', (tester) async {
    await _pumpGrid(tester, surface: const Size(360, 800), selectionActive: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机宽度多选态网格不溢出', (tester) async {
    await _pumpGrid(tester, surface: const Size(360, 800), selectionActive: true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机宽度多选态在字号上限下不溢出', (tester) async {
    await _pumpGrid(
      tester,
      surface: const Size(360, 800),
      selectionActive: true,
      textScale: 1.6,
    );
    expect(tester.takeException(), isNull);
  });
}

final List<FileNode> _files = <FileNode>[
  FileNode(
    id: 'folder-1',
    parentId: null,
    name: 'Documents',
    isFolder: true,
    nodeType: 'FOLDER',
    normalizedPath: '/Documents',
    sizeBytes: 0,
    updatedAt: DateTime(2026, 9, 24),
  ),
  FileNode(
    id: 'file-1',
    parentId: null,
    name: 'notes.txt',
    isFolder: false,
    nodeType: 'FILE',
    normalizedPath: '/notes.txt',
    mimeType: 'text/plain',
    sizeBytes: 128,
    updatedAt: DateTime(2026, 9, 24),
  ),
];
