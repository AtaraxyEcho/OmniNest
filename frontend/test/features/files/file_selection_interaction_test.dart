import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/presentation/widgets/file_grid.dart';
import 'package:omninest/features/files/presentation/widgets/file_list.dart';

void main() {
  test('桌面文件浏览器提供上传入口和文件拖放且不显示队列角标', () {
    final pageSource = Directory('lib/features/files/presentation/pages')
        .listSync()
        .whereType<File>()
        .where(
          (file) => file.uri.pathSegments.last.startsWith('file_browser_page'),
        )
        .map((file) => file.readAsStringSync())
        .join('\n');
    final dropSource =
        File(
          'lib/features/files/presentation/widgets/file_drop_upload_surface.dart',
        ).readAsStringSync();

    expect(pageSource, contains('Icons.upload_file_rounded'));
    expect(RegExp('FileDropUploadSurface\\(').allMatches(pageSource).length, 2);
    expect(pageSource, contains('openFiles()'));
    expect(pageSource, isNot(contains('_FileNavBadge')));
    expect(pageSource, contains('_fileHeaderActionButtonStyle()'));
    expect(pageSource, contains('controller.goToParent'));
    expect(pageSource, contains('state.viewMode.name'));
    expect(pageSource, contains('state.viewMode == FileBrowserViewMode.list'));
    expect(pageSource, isNot(contains('Widget _buildFileList(')));
    expect(dropSource, contains('whereType<DropItemFile>()'));
  });

  testWidgets('列表常态点击打开且多选态由长按进入', (tester) async {
    FileNode? opened;
    FileNode? previewed;
    String? selectedId;
    await tester.pumpWidget(
      _filesApp(
        FileList(
          files: _files,
          showingRecycleBin: false,
          enabled: true,
          onRename: (_) {},
          onDelete: (_) {},
          onPurge: (_) {},
          onRestore: (_) {},
          onOpen: (file) => opened = file,
          onPreview: (file) => previewed = file,
          onToggleSelection: (id) => selectedId = id,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 常态：无 Checkbox，点击直接打开/预览。
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.text('Documents'));
    expect(opened?.id, 'folder-1');
    expect(selectedId, isNull);

    await tester.tap(find.text('notes.txt'));
    expect(previewed?.id, 'file-1');
    expect(selectedId, isNull);

    // 长按行进入多选：触发选择回调，Checkbox 尚未渲染（由页面状态驱动）。
    await tester.longPress(find.text('notes.txt'));
    expect(selectedId, 'file-1');
  });

  testWidgets('列表多选态显示复选框且点击行切换选择', (tester) async {
    String? selectedId;
    FileNode? opened;
    await tester.pumpWidget(
      _filesApp(
        FileList(
          files: _files,
          showingRecycleBin: false,
          enabled: true,
          selectionActive: true,
          selectedFileIds: const {'file-1'},
          onRename: (_) {},
          onDelete: (_) {},
          onPurge: (_) {},
          onRestore: (_) {},
          onOpen: (file) => opened = file,
          onPreview: (_) {},
          onToggleSelection: (id) => selectedId = id,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(
      tester.widget<Checkbox>(find.byType(Checkbox).last).value,
      isTrue,
      reason: 'file-1 已选中',
    );

    // 多选态下点击行 = 切换选择而不是打开。
    await tester.tap(find.text('Documents'));
    expect(selectedId, 'folder-1');
    expect(opened, isNull);

    await tester.tap(find.byType(Checkbox).first);
    expect(selectedId, 'folder-1');
  });

  testWidgets('网格卡片点击文件夹时不会误触多选', (tester) async {
    FileNode? opened;
    String? selectedId;
    await tester.pumpWidget(
      _filesApp(
        SizedBox(
          width: 900,
          height: 500,
          child: FileGrid(
            files: _files,
            showingRecycleBin: false,
            enabled: true,
            onRename: (_) {},
            onDelete: (_) {},
            onPurge: (_) {},
            onRestore: (_) {},
            onOpen: (file) => opened = file,
            onPreview: (_) {},
            onToggleSelection: (id) => selectedId = id,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Documents'));
    expect(opened?.id, 'folder-1');
    expect(selectedId, isNull);

    await tester.longPress(find.text('Documents'));
    expect(selectedId, 'folder-1');
  });

  testWidgets('文件列表和网格支持键盘打开文件夹', (tester) async {
    FileNode? opened;
    await tester.pumpWidget(
      _filesApp(
        FileList(
          files: [_files.first],
          showingRecycleBin: false,
          enabled: true,
          onRename: (_) {},
          onDelete: (_) {},
          onPurge: (_) {},
          onRestore: (_) {},
          onOpen: (file) => opened = file,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened?.id, 'folder-1');

    opened = null;
    await tester.pumpWidget(
      _filesApp(
        SizedBox(
          width: 500,
          height: 300,
          child: FileGrid(
            files: [_files.first],
            showingRecycleBin: false,
            enabled: true,
            onRename: (_) {},
            onDelete: (_) {},
            onPurge: (_) {},
            onRestore: (_) {},
            onOpen: (file) => opened = file,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(opened?.id, 'folder-1');
  });
}

Widget _filesApp(Widget child) {
  return MaterialApp(
    theme: OmniNestTheme.from(AppThemePalette.dark),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
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
    updatedAt: DateTime(2026, 7, 13),
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
    updatedAt: DateTime(2026, 7, 13),
  ),
];
