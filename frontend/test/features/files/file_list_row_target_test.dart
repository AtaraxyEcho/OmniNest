import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/presentation/widgets/file_list.dart';

/// 行内操作钮原先固定 34×34，低于移动端 48 命中标准；命中区等于自身布局盒，
/// 抬高会同时改变行高与横排占位，故在手机宽度与多选态下实测。
Future<void> _pumpList(
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
          child: FileList(
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

Size _targetSize(WidgetTester tester, String tooltip) {
  // 每行都挂同一颗「更多操作」钮，取首行即可。
  return tester.getSize(find.byTooltip(tooltip).first);
}

void main() {
  testWidgets('手机宽度行内打开钮命中区达 48', (tester) async {
    await _pumpList(
      tester,
      surface: const Size(360, 800),
      selectionActive: false,
    );

    final size = _targetSize(tester, '打开');
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    // 与同行更多钮同尺寸，行高不因单颗按钮被抬高而错位。
    expect(size, _targetSize(tester, '更多操作'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机宽度多选态行内打开钮命中区达 48 且不横向溢出', (tester) async {
    await _pumpList(
      tester,
      surface: const Size(360, 800),
      selectionActive: true,
    );

    final size = _targetSize(tester, '打开');
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('命中盒抬高后行高不变', (tester) async {
    await _pumpList(
      tester,
      surface: const Size(360, 800),
      selectionActive: false,
    );

    Size rowOf(String name) => tester.getSize(
      find
          .ancestor(
            of: find.text(name),
            matching: find.byType(AnimatedContainer),
          )
          .last,
    );

    // 行 = 纵向留白 2×2 + 48 命中盒，与抬上前同为 52。
    expect(rowOf('Documents').height, 52);
    expect(rowOf('notes.txt').height, 52);
  });

  testWidgets('字号上限与多选态叠加仍不溢出', (tester) async {
    await _pumpList(
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
