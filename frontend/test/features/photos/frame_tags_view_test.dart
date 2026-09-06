import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_tags_view.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_grid_tile.dart';

class _MockPhotoRepository extends Mock implements PhotoRepository {}

/// 伪造的照片中心控制器，返回空状态以避免网络请求。
class _FakePhotoCenterController extends PhotoCenterController {
  @override
  Future<PhotoCenterState> build() async {
    return PhotoCenterState.empty();
  }
}

PhotoItem _photo(String id, String tag) {
  return PhotoItem(
    id: id,
    fileNodeId: 'file-$id',
    title: 'Photo $id',
    format: 'JPEG',
    fileSize: 1024,
    metadataStatus: 'READY',
    favorite: false,
    createdAt: DateTime(2026),
  );
}

Future<void> _pumpTagsView(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(child);
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  final photos = [_photo('photo-1', '人像'), _photo('photo-2', '人像')];

  Widget buildHarness(PhotoRepository repository) {
    return ProviderScope(
      overrides: [
        photoRepositoryProvider.overrideWithValue(repository),
        photoCenterControllerProvider.overrideWith(
          () => _FakePhotoCenterController(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        theme: OmniNestTheme.from(AppThemePalette.dark),
        home: Scaffold(
          body: FrameTagsView(onOpenPhoto: (_) {}, onToggleFavorite: (_) {}),
        ),
      ),
    );
  }

  testWidgets('点击标签芯片后显示该标签的照片瀑布流', (tester) async {
    final repository = _MockPhotoRepository();
    when(() => repository.listTags()).thenAnswer((_) async => ['人像', '风景']);
    when(
      () => repository.listByTag(any(that: equals('人像'))),
    ).thenAnswer((_) async => photos);
    when(
      () => repository.listByTag(any(that: equals('风景'))),
    ).thenAnswer((_) async => <PhotoItem>[]);
    await _pumpTagsView(tester, buildHarness(repository));

    expect(find.text('人像'), findsOneWidget);
    await tester.tap(find.text('人像'));
    await tester.pumpAndSettle();

    expect(find.text('#人像'), findsOneWidget);
    expect(find.text('2 张照片'), findsOneWidget);
    expect(find.byType(PhotoGridTile), findsNWidgets(2));
  });

  testWidgets('再次点击芯片取消选中并回到提示态', (tester) async {
    final repository = _MockPhotoRepository();
    when(() => repository.listTags()).thenAnswer((_) async => ['人像']);
    when(() => repository.listByTag(any())).thenAnswer((_) async => photos);
    await _pumpTagsView(tester, buildHarness(repository));

    await tester.tap(find.text('人像'));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoGridTile), findsNWidgets(2));

    await tester.tap(find.text('人像'));
    await tester.pumpAndSettle();
    expect(find.text('选择一个标签查看对应照片'), findsOneWidget);
    expect(find.byType(PhotoGridTile), findsNothing);
  });
}
