import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/files/media_import_ui.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_top_bar.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_empty_state.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_library_import_action.dart';

class _StubPhotoRepository implements PhotoRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakePhotoCenterController extends PhotoCenterController {
  @override
  Future<PhotoCenterState> build() async => PhotoCenterState.empty();
}

Widget _photosShell({
  required bool showImport,
  required TextEditingController searchController,
}) {
  return ProviderScope(
    overrides: [
      photoCenterControllerProvider.overrideWith(
        () => _FakePhotoCenterController(),
      ),
      photoRepositoryProvider.overrideWithValue(_StubPhotoRepository()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      theme: OmniNestTheme.dark(),
      home: Scaffold(
        body: FrameTopBar(
          view: FrameView.grid,
          searchController: searchController,
          onSearchChanged: (_) {},
          showTitle: false,
          searchExpanded: true,
          showImport: showImport,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('顶栏在非多选时显示导入入口', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _photosShell(showImport: true, searchController: controller),
    );
    await tester.pump();

    expect(find.byType(MediaImportButton), findsOneWidget);
  });

  testWidgets('顶栏在多选时隐藏导入入口', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _photosShell(showImport: false, searchController: controller),
    );
    await tester.pump();

    expect(find.byType(MediaImportButton), findsNothing);
  });

  testWidgets('空书库空态提供导入书籍主按钮', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: OmniNestTheme.dark(),
          home: const Scaffold(
            body: ReaderEmptyState(
              title: '这里还没有内容',
              subtitle: '支持 EPUB、TXT、CBZ、ZIP、PDF',
              icon: Icons.library_books_outlined,
              action: ReaderLibraryImportAction(
                style: ImportButtonStyle.filledButton,
                label: '导入书籍',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('导入书籍'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(MediaImportButton), findsOneWidget);
  });
}
