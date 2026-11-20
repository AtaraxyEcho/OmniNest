// 外部（系统文件）拖入：经由 desktop_drop 的方法通道事件驱动，
// 覆盖全屏遮罩、文件夹行高亮与「停 650ms 自动进入该目录」。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show AnimatedContainer, BoxDecoration;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/pages/desktop_files_page.dart';
import 'package:omninest/features/files/file_dashboard.dart';

import 'desktop_test_harness.dart';

final FileNode _folder = FileNode(
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

final FileNode _file = FileNode(
  id: 'f-1',
  parentId: null,
  name: 'Budget review.pdf',
  isFolder: false,
  nodeType: 'DOCUMENT',
  normalizedPath: '/OmniCloud/Budget review.pdf',
  sizeBytes: 1100000,
  updatedAt: DateTime(2026, 10, 28),
  spaceType: SpaceType.personal,
);

/// 记录 folder 打开的控制器：`openFolder` 是类方法，可直接覆写。
class _RecordingFileBrowser extends FileBrowserController {
  @override
  Future<FileBrowserState> build() async => FileBrowserState(
    files: [_folder, _file],
    recycleBin: const <FileNode>[],
    breadcrumbs: const <FileNode>[],
    fileTotalElements: 2,
    fileTotalPages: 1,
  );

  final List<String> openedFolders = <String>[];

  @override
  Future<void> loadSection(
    FileManagerSection section, {
    bool background = false,
  }) async {}

  @override
  Future<void> openFolder(
    FileNode folder, {
    List<FileNode>? breadcrumbs,
  }) async {
    openedFolders.add(folder.id);
  }
}

/// 平台 → Dart 方向的拖拽事件（`desktop_drop` 的方法通道协议）。
Future<void> _dragEvent(WidgetTester tester, String method, Offset at) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'desktop_drop',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall(method, <double>[at.dx, at.dy]),
    ),
    (_) {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('外部拖入：遮罩出现、文件夹行高亮，停 650ms 后进入该目录', (tester) async {
    // 拖放能力只在桌面平台开启（DropTarget 的 enable 由 PlatformCapabilities 决定）。
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      tester.view.physicalSize = kDesktopViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = _RecordingFileBrowser();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...desktopSeedOverrides(),
            fileBrowserControllerProvider.overrideWith(() => controller),
          ],
          child: wrapDesktop(const DesktopFilesPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      final folderCenter = tester.getCenter(find.text('Studio archive'));
      final fileCenter = tester.getCenter(find.text('Budget review.pdf'));

      BoxDecoration? rowDecoration(String name) {
        final row =
            find
                .ancestor(
                  of: find.text(name),
                  matching: find.byType(AnimatedContainer),
                )
                .first;
        return tester.widget<AnimatedContainer>(row).foregroundDecoration
            as BoxDecoration?;
      }

      // 1) 进入窗口：整页遮罩浮起。
      await _dragEvent(tester, 'entered', folderCenter);
      await tester.pump();
      expect(find.text('Drop to upload'), findsOneWidget);

      // 2) 指针移到文件夹行上：该行按 `.f-row.drop` 高亮，文件行不高亮。
      await _dragEvent(tester, 'updated', folderCenter);
      await tester.pump();
      expect(rowDecoration('Studio archive')?.border?.top.width, 2);
      expect(rowDecoration('Budget review.pdf'), isNull);

      // 3) 停满 650ms：目录自动打开。
      expect(controller.openedFolders, isEmpty);
      await tester.pump(const Duration(milliseconds: 700));
      expect(controller.openedFolders, <String>['d-1']);

      // 4) 指针移出窗口：遮罩与高亮一起收起。
      await _dragEvent(tester, 'updated', fileCenter);
      await tester.pump();
      await _dragEvent(tester, 'exited', fileCenter);
      await tester.pump();
      expect(find.text('Drop to upload'), findsNothing);
      expect(rowDecoration('Studio archive'), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
