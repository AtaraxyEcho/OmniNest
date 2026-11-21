import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/pages/desktop_files_page.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/features/files/file_dashboard.dart';

import 'desktop_test_harness.dart';

/// 文件页的种子控制器：只覆盖 `build` 与树/分区的取数，
/// 选中、排序、分类这些局部动作仍走真实实现（它们只改内存态）。
class SeededFileBrowser extends FileBrowserController {
  SeededFileBrowser(this.seed);

  final FileBrowserState seed;

  @override
  Future<FileBrowserState> build() async => seed;

  @override
  Future<void> loadSection(
    FileManagerSection section, {
    bool background = false,
  }) async {}
}

final FileNode seededFolder = FileNode(
  id: 'd-1',
  parentId: null,
  name: 'Studio archive',
  isFolder: true,
  nodeType: 'FOLDER',
  normalizedPath: '/OmniCloud/Studio archive',
  sizeBytes: 0,
  updatedAt: DateTime(2026, 11, 2),
  spaceType: SpaceType.personal,
);

final FileNode seededPdf = FileNode(
  id: 'f-1',
  parentId: null,
  name: 'Budget review.pdf',
  isFolder: false,
  nodeType: 'DOCUMENT',
  normalizedPath: '/OmniCloud/Budget review.pdf',
  sizeBytes: 1100000,
  mimeType: 'application/pdf',
  updatedAt: DateTime(2026, 10, 28),
  spaceType: SpaceType.personal,
);

final FileNode seededVideo = FileNode(
  id: 'f-2',
  parentId: null,
  name: 'Studio reel.mov',
  isFolder: false,
  nodeType: 'VIDEO',
  normalizedPath: '/OmniCloud/Studio reel.mov',
  sizeBytes: 612000000,
  mimeType: 'video/quicktime',
  updatedAt: DateTime(2026, 10, 20),
  spaceType: SpaceType.personal,
  favorited: true,
);

FileBrowserState seededFilesState({FileManagerSection? section}) =>
    FileBrowserState(
      section: section ?? FileManagerSection.allFiles,
      files: [seededFolder, seededPdf, seededVideo],
      recycleBin:
          section == FileManagerSection.recycleBin
              ? [seededPdf]
              : const <FileNode>[],
      recentFiles: [seededPdf, seededVideo],
      favoriteFiles: [seededVideo],
      breadcrumbs: const <FileNode>[],
      fileTotalElements: 3,
      fileTotalPages: 1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpFiles(WidgetTester tester, {FileBrowserState? state}) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final seed = state ?? seededFilesState();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...desktopSeedOverrides(),
          fileBrowserControllerProvider.overrideWith(
            () => SeededFileBrowser(seed),
          ),
        ],
        child: wrapDesktop(const DesktopFilesPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('列表按文件夹/文件分组并显示大小与访问态', (tester) async {
    await pumpFiles(tester);

    expect(find.text('My files'), findsWidgets);
    expect(find.text('Studio archive'), findsWidgets);
    expect(find.text('Budget review.pdf'), findsOneWidget);
    expect(find.text('Studio reel.mov'), findsOneWidget);
    expect(find.text('FOLDERS'), findsOneWidget);
    expect(find.text('FILES'), findsOneWidget);
    // 目录不给大小，只给破折号；文件给格式化后的体积。
    expect(find.text('1.0 MB'), findsWidgets);
  });

  testWidgets('结构树顶部提供个人与共享空间切换', (tester) async {
    await pumpFiles(tester);

    expect(find.byTooltip('Personal Space'), findsOneWidget);
    expect(find.byTooltip('Shared Space'), findsOneWidget);
  });

  testWidgets('共享空间显示原型页头、真实用量卡和共享空态', (tester) async {
    await pumpFiles(
      tester,
      state: FileBrowserState(
        files: const <FileNode>[],
        recycleBin: const <FileNode>[],
        spaceType: 'SHARED',
        sharedSpaceUsage: const SharedSpaceUsage(
          usedBytes: 512 * 1024 * 1024,
          maxBytes: 2 * 1024 * 1024 * 1024,
          fileCount: 0,
        ),
        fileTotalPages: 1,
      ),
    );

    expect(find.text('Shared Space'), findsWidgets);
    expect(find.text('My files'), findsNothing);
    expect(find.text('Household space'), findsOneWidget);
    expect(find.text('No files in shared space'), findsOneWidget);
  });

  testWidgets('共享选择栏提供移回个人空间和共享删除动作', (tester) async {
    await pumpFiles(
      tester,
      state: FileBrowserState(
        files: [
          FileNode(
            id: 'shared-1',
            parentId: null,
            name: 'Shared report.pdf',
            isFolder: false,
            nodeType: 'DOCUMENT',
            normalizedPath: '/Shared/Shared report.pdf',
            sizeBytes: 1024,
            mimeType: 'application/pdf',
            updatedAt: DateTime(2026, 11, 2),
            spaceType: SpaceType.shared,
            uploaderName: 'Alex',
          ),
        ],
        recycleBin: const <FileNode>[],
        spaceType: 'SHARED',
        selectedFileIds: const {'shared-1'},
        fileTotalElements: 1,
        fileTotalPages: 1,
      ),
    );

    expect(find.text('Move to Personal Space'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Share'), findsNothing);
    expect(find.text('Move to Recycle'), findsNothing);
  });

  testWidgets('新建文件夹先在当前列表进入就地命名态', (tester) async {
    await pumpFiles(tester);

    await tester.tap(find.text('New Folder'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('New Folder'), findsWidgets);
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('搜索按名称过滤主列表', (tester) async {
    await pumpFiles(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('desktop-files-search')),
      'reel',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Studio reel.mov'), findsOneWidget);
    expect(find.text('Budget review.pdf'), findsNothing);
  });

  testWidgets('点选一行出现多选操作栏', (tester) async {
    await pumpFiles(tester);

    await tester.tap(find.text('Budget review.pdf'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Move to Recycle'), findsOneWidget);
  });

  testWidgets('工具栏给 5 颗 chip，点文件夹只留下目录', (tester) async {
    await pumpFiles(tester);

    // 样例 `Files.tsx:334`：All / Folders / Documents / Images / Media。
    for (final label in ['All', 'Folders', 'Documents', 'Images', 'Media']) {
      expect(find.text(label), findsOneWidget, reason: '缺少 $label chip');
    }

    await tester.tap(find.text('Folders'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Studio archive'), findsOneWidget);
    expect(find.text('Budget review.pdf'), findsNothing);
    expect(find.text('Studio reel.mov'), findsNothing);
  });

  testWidgets('视图切换在工具栏右侧，与搜索框同一行', (tester) async {
    await pumpFiles(tester);

    final toggle = find.byTooltip('Grid view');
    expect(toggle, findsOneWidget);
    expect(find.byTooltip('List view'), findsOneWidget);

    // 同一行意味着纵向中心重合；页头里不该再有第二份切换钮。
    expect(
      tester.getCenter(toggle).dy,
      moreOrLessEquals(
        tester
            .getCenter(
              find.byKey(const ValueKey<String>('desktop-files-search')),
            )
            .dy,
        epsilon: 1,
      ),
    );
    // 30×28 的内块 + 3px 内边距 + 1px 描边。
    expect(tester.getSize(toggle).height, 28);
  });

  testWidgets('网格视图把文件画成卡片', (tester) async {
    await pumpFiles(tester);

    await tester.tap(find.byTooltip('Grid view'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    // v11 网格按样例补了 Folders/Files 分组标签，文件名仍在。
    expect(find.text('Studio reel.mov'), findsOneWidget);
    expect(find.text('FOLDERS'), findsOneWidget);
    expect(find.text('FILES'), findsOneWidget);
  });

  testWidgets('表头与数据行同列对齐，行内动作默认收起', (tester) async {
    await pumpFiles(tester);

    double leftOf(Finder finder) => tester.getTopLeft(finder).dx;

    // 表头与行共用一份列宽（22 / 40 / flex / 112 / 84 / 150 / 108 + gap 14）。
    expect(
      leftOf(find.text('Title')),
      moreOrLessEquals(leftOf(find.text('Budget review.pdf')), epsilon: 0.5),
    );
    expect(
      leftOf(find.text('Modified')),
      moreOrLessEquals(leftOf(find.text('Oct 28')), epsilon: 0.5),
    );

    List<double> actionOpacities() =>
        tester
            .widgetList<AnimatedOpacity>(
              find.ancestor(
                of: find.byTooltip('Open file menu'),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .map((widget) => widget.opacity)
            .toList();

    // 样例 `.ra{opacity:0}`：没悬停也没选中时不显示行内动作。
    expect(actionOpacities(), everyElement(0));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Studio reel.mov')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(actionOpacities(), contains(1));
  });

  testWidgets('搜索框在有内容时给出清除钮', (tester) async {
    await pumpFiles(tester);

    final field = find.byKey(const ValueKey<String>('desktop-files-search'));
    expect(find.byTooltip('Clear search'), findsNothing);

    await tester.enterText(field, 'reel');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('Budget review.pdf'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Budget review.pdf'), findsOneWidget);
    expect(find.byTooltip('Clear search'), findsNothing);
  });

  testWidgets('行首复选块把选中态交给语义', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpFiles(tester);

    // 行内所有文本会被合并成一个节点，复选态经 hasCheckedState 一起暴露。
    // v11 把复选语义放在行首独立 tick 上（不再与文本节点合并）。
    final ticks = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.checked == false,
    );
    expect(ticks, findsWidgets);
    // 选中提示与行文本分属两个语义节点，改查 tick 自己的 label。
    expect(
      tester.getSemantics(ticks.first).getSemanticsData().label,
      contains('Select this row'),
    );

    await tester.tap(find.text('Budget review.pdf'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.checked == true,
      ),
      findsWidgets,
    );
    handle.dispose();
  });

  testWidgets('行内三件套按样例给尺寸：行圆角 12 / 图舱 38 / 复选框 18', (tester) async {
    await pumpFiles(tester);

    final row =
        find
            .ancestor(
              of: find.text('Budget review.pdf'),
              matching: find.byType(AnimatedContainer),
            )
            .first;
    final rowBox = tester.widget<AnimatedContainer>(row);
    expect(
      (rowBox.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(DesktopMetrics.radius),
    );

    List<Size> sizesOf(Finder finder) => [
      for (var i = 0; i < finder.evaluate().length; i++)
        tester.getSize(finder.at(i)),
    ];
    expect(
      sizesOf(find.descendant(of: row, matching: find.byType(Container))),
      contains(const Size(38, 38)),
    );
    expect(
      sizesOf(
        find.descendant(of: row, matching: find.byType(AnimatedContainer)),
      ),
      contains(const Size(18, 18)),
    );
  });

  testWidgets('表头吸顶：列表滚动时表头不动', (tester) async {
    // 40 行足以让列表区溢出，才谈得上滚动。
    final many = [
      for (var i = 0; i < 40; i++)
        FileNode(
          id: 'm-$i',
          parentId: null,
          name: 'Document ${i.toString().padLeft(2, '0')}.pdf',
          isFolder: false,
          nodeType: 'DOCUMENT',
          normalizedPath: '/OmniCloud/Document $i.pdf',
          sizeBytes: 1200000,
          updatedAt: DateTime(2026, 10, 28),
          spaceType: SpaceType.personal,
        ),
    ];
    await pumpFiles(
      tester,
      state: FileBrowserState(
        files: many,
        recycleBin: const <FileNode>[],
        recentFiles: many,
        breadcrumbs: const <FileNode>[],
        fileTotalElements: many.length,
        fileTotalPages: 1,
      ),
    );

    final headerTop = tester.getTopLeft(find.text('Title')).dy;
    // 第 5 行在 -260 的位移后仍然可见（SliverList 只建可见行，第 0 行会被回收）。
    final anchorTop = tester.getTopLeft(find.text('Document 05.pdf')).dy;

    // 列表区是唯一含行内容的滚动视图（侧栏另有一层，不含行）；
    // 表头是 pinned 的 sliver，行在它下方滚动。
    final listScroll =
        find
            .ancestor(
              of: find.text('Document 05.pdf'),
              matching: find.byType(CustomScrollView),
            )
            .first;
    await tester.drag(listScroll, const Offset(0, -260));
    await tester.pump();
    // 行上的双击识别器会挂一个 40ms 定时器，pump 掉再收尾。
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.getTopLeft(find.text('Title')).dy, headerTop);
    expect(
      tester.getTopLeft(find.text('Document 05.pdf')).dy,
      lessThan(anchorTop),
    );
    expect(find.text('Title'), findsOneWidget);
    // 行真的会滑到表头底下，模糊层必须有可见对象（样例 `backdrop-filter`）。
    // 主区玻璃面板与吸顶表头各自保留一层模糊，避免表头滚动时失去
    // 原型 `.fx-main` / `.f-head` 的层级。
    expect(
      find.ancestor(
        of: find.text('Title'),
        matching: find.byType(BackdropFilter),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('拖动行悬停在文件夹上时按 .f-row.drop 高亮', (tester) async {
    await pumpFiles(tester);

    // 桌面拖拽由鼠标即时触发，先发一次 hover 让行切换到 Draggable；
    // 触摸指针仍走长按，测试不能拿默认 touch 指针冒充鼠标。
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final start = tester.getCenter(find.text('Budget review.pdf'));
    await tester.sendEventToBinding(pointer.hover(start));
    await tester.pump();
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('Studio archive')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    BoxDecoration? folderDecoration() {
      final row =
          find
              .ancestor(
                of: find.text('Studio archive'),
                matching: find.byType(AnimatedContainer),
              )
              .first;
      return tester.widget<AnimatedContainer>(row).foregroundDecoration
          as BoxDecoration?;
    }

    // 样例 `.f-row.drop`：2px 实描边（底色的 accent 24% 一起上）。
    final decoration = folderDecoration();
    expect(decoration, isNotNull);
    expect(decoration!.border!.top.width, 2);
    expect(decoration.border!.top.color.a, 1);

    // 拖到文件行上不该有任何落点高亮。
    await gesture.moveTo(tester.getCenter(find.text('Studio reel.mov')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(folderDecoration(), isNull);

    // 取消拖拽，别触发真正的移动（该动作要仓库，本用例只验视觉）。
    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 320));
    expect(folderDecoration(), isNull);
  });

  testWidgets('空文件夹给出空态而不是空白', (tester) async {
    await pumpFiles(
      tester,
      state: const FileBrowserState(
        files: <FileNode>[],
        recycleBin: <FileNode>[],
      ),
    );

    expect(
      find.text('This folder is empty. Drop files here or press Upload.'),
      findsOneWidget,
    );
  });
}
