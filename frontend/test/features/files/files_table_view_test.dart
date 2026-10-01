import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/files/application/file_browser_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/presentation/widgets/file_node_actions.dart';
import 'package:omninest/features/files/presentation/widgets/files_check_mark.dart';
import 'package:omninest/features/files/presentation/widgets/files_table_view.dart';
import 'package:omninest/features/files/presentation/theme/files_workstation_theme.dart';

Future<void> _pumpTable(
  WidgetTester tester, {
  required Size surface,
  FileBrowserSortBy sortBy = FileBrowserSortBy.name,
  ValueChanged<FileBrowserSortBy>? onSortByChanged,
  void Function(String id)? onToggleSelection,
  void Function(FileNode file)? onOpen,
  void Function(FileNode file)? onPreview,
  void Function(FileNode file)? onDownload,
  void Function(FileNode file)? onShare,
  void Function(FileNode file)? onToggleFavorite,
  void Function(String id)? onInspect,
  VoidCallback? onToggleSelectAll,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final actions = FileNodeActionCallbacks(
    onRename: (_) {},
    onDelete: (_) {},
    onPurge: (_) {},
    onRestore: (_) {},
    onOpen: (file) => onOpen?.call(file),
    onPreview: (file) => onPreview?.call(file),
    onDownload: (file) => onDownload?.call(file),
    onShare: (file) => onShare?.call(file),
    onToggleFavorite: (file) => onToggleFavorite?.call(file),
    onToggleSelection: (id) => onToggleSelection?.call(id),
    onInspect: (id) => onInspect?.call(id),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: OmniNestTheme.from(AppThemePalette.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: FilesWorkstationScope(
          child: FileTableView(
            files: _files,
            showingRecycleBin: false,
            enabled: true,
            actions: actions,
            sortBy: sortBy,
            onSortByChanged: onSortByChanged,
            selectionActive: false,
            onToggleSelectAll: onToggleSelectAll,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
    uploadedBy: 'admin',
  ),
  FileNode(
    id: 'file-1',
    parentId: null,
    name: 'notes.txt',
    isFolder: false,
    nodeType: 'FILE',
    normalizedPath: '/notes.txt',
    sizeBytes: 1024,
    mimeType: 'text/plain',
    updatedAt: DateTime(2026, 9, 25),
    uploadedBy: 'admin',
  ),
];

void main() {
  testWidgets('渲染 mono 表头与 ✔ 勾选列且默认全部未勾选', (tester) async {
    await _pumpTable(tester, surface: const Size(1000, 800));
    expect(find.text('名称'), findsOneWidget);
    expect(find.text('修改时间'), findsOneWidget);
    expect(find.text('大小'), findsOneWidget);
    expect(find.byType(FilesCheckMark), findsNWidgets(3)); // 表头全选 + 两行
    for (final mark in tester.widgetList<FilesCheckMark>(
      find.byType(FilesCheckMark),
    )) {
      expect(mark.value, isFalse);
    }
  });

  testWidgets('点击表头触发排序回调', (tester) async {
    final picked = <FileBrowserSortBy>[];
    await _pumpTable(
      tester,
      surface: const Size(1000, 800),
      onSortByChanged: picked.add,
    );
    await tester.tap(find.text('修改时间'));
    expect(picked, [FileBrowserSortBy.updatedAt]);
  });

  testWidgets('多字段自适应列：格式560/上传者780/MIME960/路径1200 渐进展开，节点 ID 不展示', (
    tester,
  ) async {
    await _pumpTable(tester, surface: const Size(1000, 800));
    expect(find.text('格式'), findsOneWidget);
    expect(find.text('TXT 小说'), findsOneWidget);
    expect(find.text('文件夹'), findsOneWidget);
    expect(find.text('上传者'), findsOneWidget);
    expect(find.text('admin'), findsNWidgets(2), reason: '上传者列渲染文件行值');
    expect(find.text('MIME'), findsOneWidget);
    expect(find.text('text/plain'), findsOneWidget);
    expect(find.text('路径'), findsNothing, reason: '1000px 未达路径列阈值');
    expect(find.text('节点 ID'), findsNothing);

    await _pumpTable(tester, surface: const Size(640, 800));
    expect(find.text('格式'), findsOneWidget);
    expect(find.text('上传者'), findsNothing, reason: '窄视口收起上传者列');
    expect(find.text('admin'), findsNothing);
    expect(find.text('MIME'), findsNothing);

    await _pumpTable(tester, surface: const Size(1280, 800));
    expect(find.text('路径'), findsOneWidget, reason: '宽屏展开路径弹性列');
    expect(find.text('/Documents'), findsOneWidget);
    expect(find.text('/notes.txt'), findsOneWidget);
  });

  testWidgets('操作列常驻：收藏/分享/预览/下载不悬停即可见可点，⋯菜单不再重复快捷项', (tester) async {
    final previewed = <String>[];
    final shared = <String>[];
    await _pumpTable(
      tester,
      surface: const Size(1000, 800),
      onPreview: (file) => previewed.add(file.id),
      onShare: (file) => shared.add(file.id),
    );
    // 四个快捷钮对文件行常驻可见（不悬停、不勾选、不检视）。
    expect(
      find.byIcon(Icons.star_border_rounded),
      findsOneWidget,
      reason: '未收藏星标为描边态',
    );
    expect(find.byIcon(Icons.share_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);

    // 未悬停直接点击即可触发（行双击识别器消歧需 pump 400ms）。
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(previewed, ['file-1']);
    await tester.tap(find.byIcon(Icons.share_outlined));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(shared, ['file-1']);

    // ⋯ 菜单保留重命名/删除，剔除已内联的四个快捷项。
    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('分享'), findsNothing, reason: '分享已内联操作列');
    expect(find.text('预览'), findsNothing, reason: '预览已内联操作列');
    expect(find.text('下载'), findsNothing, reason: '下载已内联操作列');
    expect(find.text('收藏'), findsNothing, reason: '收藏已内联操作列');
  });

  testWidgets('表头全选框：初始未勾选，点击触发全选回调', (tester) async {
    var toggled = 0;
    await _pumpTable(
      tester,
      surface: const Size(1000, 800),
      onToggleSelectAll: () => toggled++,
    );
    final headerMark = find.byType(FilesCheckMark).first;

    final mark = tester.widget<FilesCheckMark>(headerMark);
    expect(mark.value, isFalse, reason: '初始无选择，表头为未勾选态');
    expect(mark.indeterminate, isFalse);

    await tester.tap(headerMark);
    await tester.pump(const Duration(milliseconds: 400));
    expect(toggled, 1, reason: '点击表头触发全选/清空切换回调');
  });

  testWidgets('行单击检视、双击打开/预览，勾选列切换选择', (tester) async {
    final opened = <String>[];
    final previewed = <String>[];
    final selected = <String>[];
    final inspected = <String>[];
    await _pumpTable(
      tester,
      surface: const Size(1000, 800),
      onOpen: (file) => opened.add(file.id),
      onPreview: (file) => previewed.add(file.id),
      onToggleSelection: selected.add,
      onInspect: inspected.add,
    );
    await tester.tap(find.text('Documents'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(inspected, ['folder-1']);
    expect(opened, isEmpty);
    await tester.tap(find.text('Documents'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Documents'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(opened, ['folder-1']);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('notes.txt'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('notes.txt'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(previewed, ['file-1']);
    await tester.tap(find.byType(FilesCheckMark).at(1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(selected, ['folder-1']);
  });

  test('双视图批量栏源码互斥：网格一体化栏仅在 grid 分支渲染', () {
    final source =
        File(
          'lib/features/files/presentation/pages/file_browser_page_workspace.dart',
        ).readAsStringSync();
    expect(source, contains('if (state.viewMode == FileBrowserViewMode.grid)'));
    expect(source, contains('_GridBatchToolbar(state: state)'));
    expect(source, contains('_TableBatchBar(state: state)'));
    final gridIndex = source.indexOf('_GridBatchToolbar(state: state)');
    final tableIndex = source.indexOf('_TableBatchBar(state: state)');
    expect(gridIndex, greaterThan(-1));
    expect(tableIndex, greaterThan(-1));
  });

  test('视图切换为 180ms 淡入微移且起点 0.35 opacity', () {
    final source =
        File(
          'lib/features/files/presentation/pages/file_browser_page_workspace.dart',
        ).readAsStringSync();
    expect(source, contains('MotionToken.pageSwitch'));
    expect(source, contains('Tween(begin: 0.35, end: 1.0)'));
  });
}
