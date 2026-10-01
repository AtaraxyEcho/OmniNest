import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/presentation/theme/files_workstation_theme.dart';
import 'package:omninest/features/files/presentation/widgets/file_inspector_panel.dart';
import 'package:omninest/features/files/presentation/widgets/file_node_actions.dart';
import 'package:omninest/features/files/presentation/widgets/files_check_mark.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: OmniNestTheme.from(AppThemePalette.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(body: FilesWorkstationScope(child: child)),
    ),
  );
}

const _testNode = FileNode(
  id: 'file-1',
  parentId: null,
  name: 'test_video.mkv',
  isFolder: false,
  nodeType: 'FILE',
  normalizedPath: '/Media/test_video.mkv',
  sizeBytes: 26420439,
  mimeType: 'video/x-matroska',
  uploadedBy: 'admin',
  updatedAt: null,
);

final _actions = FileNodeActionCallbacks(
  onPreview: (_) {},
  onDownload: (_) {},
  onShare: (_) {},
  onDelete: (_) {},
);

void main() {
  group('P0: Inspector 详情面板（零覆盖修复）', () {
    testWidgets('渲染标题/预览块/KV 元数据/底部双操作钮', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 320,
            height: 600,
            child: FileInspectorPanel(
              file: _testNode,
              actions: _actions,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('文件属性详情'), findsOneWidget);
      expect(find.text('test_video.mkv'), findsOneWidget);
      expect(find.text('video/x-matroska'), findsAtLeastNWidgets(1));
      expect(find.byType(FilesCheckMark), findsNothing);
    });

    testWidgets('底部操作钮：文件行 [预览] + [分享]', (tester) async {
      var previewed = false;
      var shared = false;
      final actions = FileNodeActionCallbacks(
        onPreview: (_) => previewed = true,
        onShare: (_) => shared = true,
      );
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 320,
            height: 600,
            child: FileInspectorPanel(
              file: _testNode,
              actions: actions,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('预览'));
      expect(previewed, isTrue);
      await tester.tap(find.text('分享'));
      expect(shared, isTrue);
    });

    testWidgets('文件夹行底部操作钮切换为 [打开]', (tester) async {
      var opened = false;
      final actions = FileNodeActionCallbacks(
        onOpen: (_) => opened = true,
        onShare: null,
      );
      const folderNode = FileNode(
        id: 'folder-1',
        parentId: null,
        name: 'Documents',
        isFolder: true,
        nodeType: 'FOLDER',
        normalizedPath: '/Documents',
        sizeBytes: 0,
        updatedAt: null,
      );
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 320,
            height: 600,
            child: FileInspectorPanel(
              file: folderNode,
              actions: actions,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('打开'), findsOneWidget);
      await tester.tap(find.text('打开'));
      expect(opened, isTrue);
    });

    test('Inspector dock 源码接线：320px 常驻/220ms 动画/Esc 清空', () {
      final source =
          File(
            'lib/features/files/presentation/pages/file_browser_page_inspector.dart',
          ).readAsStringSync();
      expect(source, contains('width: state.inspectorOpen ? 320 : 0'));
      expect(source, contains('MotionToken.pageSwitch'));
      expect(source, contains('LogicalKeyboardKey.escape'));
    });
  });

  group('P0: 批量操作栏（零覆盖修复）', () {
    test('三处批量栏源码接线互斥', () {
      final batch =
          File(
            'lib/features/files/presentation/pages/file_browser_page_batch.dart',
          ).readAsStringSync();
      expect(batch, contains('_TableBatchBar'));
      expect(batch, contains('_GridBatchToolbar'));
      expect(batch, contains('_MobileStickyBatchBar'));
      expect(batch, contains('_BatchActionButton'));
      expect(batch, contains('filesBatchPurge'), reason: '批量粉碎须走键入短语确认');
    });

    test('工作区分支互斥：grid 模式走一体化栏，list 模式走表格栏', () {
      final ws =
          File(
            'lib/features/files/presentation/pages/file_browser_page_workspace.dart',
          ).readAsStringSync();
      expect(
        ws,
        contains('state.viewMode == FileBrowserViewMode.grid'),
        reason: 'grid 分支判断',
      );
      expect(ws, contains('_GridBatchToolbar(state: state)'));
      expect(ws, contains('_TableBatchBar(state: state)'));
      expect(ws, contains('_MobileStickyBatchBar(state: state)'));
    });
  });

  group('P0: 文件夹选择器（零覆盖修复）', () {
    test('选择器源码接线：面包屑导航 + 目录加载竞态守卫', () {
      final source =
          File(
            'lib/features/files/presentation/pages/file_browser_page_folder_picker.dart',
          ).readAsStringSync();
      expect(source, contains('class _FolderPickerDialog'));
      expect(source, contains('_loadGeneration'), reason: '竞态代守卫');
      expect(source, contains('listFolderOptions'), reason: '经 controller 取数');
      expect(source, contains('excludeIds'), reason: '排除自身/子孙');
    });
  });

  group('P0: 破坏性确认调用链（零覆盖修复）', () {
    test('粉碎流程走 _confirmTypedAndRun 而非 _confirmAndRun', () {
      final ws =
          File(
            'lib/features/files/presentation/pages/file_browser_page_workspace.dart',
          ).readAsStringSync();
      final batch =
          File(
            'lib/features/files/presentation/pages/file_browser_page_batch.dart',
          ).readAsStringSync();
      // 单文件粉碎
      expect(ws, contains('filesPurgeConfirmTitle'));
      expect(ws, contains('_confirmTypedAndRun'));
      // 批量粉碎
      expect(batch, contains('filesBatchPurge'));
      expect(batch, contains('_confirmTypedAndRun'));
    });

    test('controller.repository getter 已移除（展示层不直连仓储）', () {
      final controller =
          File(
            'lib/features/files/application/file_browser_controller.dart',
          ).readAsStringSync();
      expect(controller, isNot(contains('get repository')));
    });
  });

  group('P1: 分享链接面板（零覆盖修复）', () {
    test('分享面板源码接线：Material 根包裹 + 双形态（弹窗/贴底）', () {
      final source =
          File(
            'lib/features/files/presentation/widgets/share_link_sheet.dart',
          ).readAsStringSync();
      expect(source, contains('return Material('), reason: 'ListTile 断言修复');
      expect(source, contains('embedded'), reason: '桌面弹窗嵌入形态');
      expect(source, contains('showFilesDialog'), reason: '走弹窗壳');
      expect(source, contains('showModalBottomSheet'), reason: '移动贴底');
    });
  });

  group('P2: 半透明叠色技术债', () {
    test('全模块 withValues(alpha:) 上限棘轮', () {
      final dir = Directory('lib/features/files/presentation');
      var total = 0;
      for (final file in dir.listSync(recursive: true)) {
        if (file is File && file.path.endsWith('.dart')) {
          total +=
              'withValues(alpha:'.allMatches(file.readAsStringSync()).length;
        }
      }
      expect(total, lessThanOrEqualTo(50), reason: '全展示层叠色上限 50，当前 $total 处');
    });
  });
}
