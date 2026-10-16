// 照片子页托管形态回归：相册详情、查看器与相册选片页在移动壳层内
// 必须落深玻璃皮肤（样例 photos-overlay / photo-viewer / picker-grid），
// 而不是继续用 Frame 暖纸顶栏。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:omninest/features/photos/presentation/pages/photo_album_detail_page.dart';
import 'package:omninest/features/photos/presentation/pages/photo_album_photo_picker_page.dart';
import 'package:omninest/features/photos/presentation/pages/photo_detail_page.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_hosted_chrome.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_viewer_chrome.dart';

class _MockPhotoRepository extends Mock implements PhotoRepository {}

/// 空状态的照片中心桩：相册分页与分享动作不触达真实网络。
class _FakePhotoCenterController extends PhotoCenterController {
  @override
  Future<PhotoCenterState> build() async => PhotoCenterState.empty();

  @override
  Future<void> refresh() async {}

  @override
  Future<void> loadTimeline({bool force = false}) async {}
}

/// 无封面 URL 的照片：托管格与舞台都走占位分支，测试不产生网络请求。
PhotoItem _photo(String id, {String? city}) {
  return PhotoItem(
    id: id,
    fileNodeId: 'file-$id',
    title: 'Photo $id',
    format: 'JPEG',
    fileSize: 1024,
    metadataStatus: 'READY',
    favorite: false,
    createdAt: DateTime(2024, 11, 12, 18, 24),
    dateTaken: DateTime(2024, 11, 12, 18, 24),
    gpsLocation: city == null ? null : <String, dynamic>{'city': city},
  );
}

PhotoAlbum _album(int photoCount) {
  return PhotoAlbum(
    id: 'album-1',
    name: 'Golden hour',
    description: '',
    photoCount: photoCount,
    createdAt: DateTime(2024, 11, 1),
    updatedAt: DateTime(2024, 11, 12),
  );
}

void _stubRepository(
  _MockPhotoRepository repository,
  List<PhotoItem> albumPhotos,
) {
  when(() => repository.getAlbumDetail(any())).thenAnswer(
    (_) async => PhotoAlbumDetail(
      album: _album(albumPhotos.length),
      photos: albumPhotos,
    ),
  );
  when(() => repository.getPhoto(any())).thenAnswer(
    (invocation) async => albumPhotos.firstWhere(
      (p) => p.id == invocation.positionalArguments[0],
      orElse: () => _photo(invocation.positionalArguments[0] as String),
    ),
  );
  when(
    () => repository.listAlbumPhotos(
      albumId: any(named: 'albumId'),
      page: any(named: 'page'),
      size: any(named: 'size'),
    ),
  ).thenAnswer((_) async => PhotoPage.empty());
  when(
    () => repository.listAlbumCandidates(
      albumId: any(named: 'albumId'),
      page: any(named: 'page'),
      size: any(named: 'size'),
    ),
  ).thenAnswer(
    (_) async => PhotoPage(
      items: [_photo('c-1'), _photo('c-2')],
      page: 0,
      size: 50,
      totalElements: 2,
      totalPages: 1,
    ),
  );
}

Future<void> _pumpHostedPhone(
  WidgetTester tester, {
  required String initialLocation,
  required _MockPhotoRepository repository,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/photos',
        builder:
            (context, state) =>
                const Scaffold(body: Center(child: Text('Photos Home'))),
      ),
      GoRoute(
        path: '/photos/albums/:albumId',
        builder:
            (context, state) =>
                PhotoAlbumDetailPage(albumId: state.pathParameters['albumId']!),
      ),
      GoRoute(
        path: '/photos/albums/:albumId/add',
        builder:
            (context, state) => PhotoAlbumPhotoPickerPage(
              albumId: state.pathParameters['albumId']!,
            ),
      ),
      GoRoute(
        path: '/photos/:photoId',
        builder:
            (context, state) =>
                PhotoDetailPage(photoId: state.pathParameters['photoId']!),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        photoRepositoryProvider.overrideWithValue(repository),
        photoCenterControllerProvider.overrideWith(
          () => _FakePhotoCenterController(),
        ),
      ],
      child: MobileShellScope(
        hosted: true,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: OmniNestTheme.from(AppThemePalette.dark),
        ),
      ),
    ),
  );
  // 常驻动画（加载指示/骨架）会让 pumpAndSettle 永不收敛，改用固定帧推进。
  for (final step in [
    const Duration(milliseconds: 50),
    const Duration(milliseconds: 120),
    const Duration(milliseconds: 240),
  ]) {
    await tester.pump(step);
  }
}

Future<void> _settleTap(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  testWidgets('相册详情托管态：玻璃横幅 + 工具行 + 三列网格首格加卡', (tester) async {
    final repository = _MockPhotoRepository();
    _stubRepository(repository, [_photo('p-1'), _photo('p-2')]);

    await _pumpHostedPhone(
      tester,
      initialLocation: '/photos/albums/album-1',
      repository: repository,
    );

    expect(find.byType(MobileModuleHeader), findsOneWidget);
    expect(find.text('Golden hour'), findsOneWidget);
    expect(find.byType(EnvEmptyState), findsNothing);
    // 首格加卡保留，照片格按已加载数量渲染。
    expect(find.byType(PhotoHostedAddTile), findsOneWidget);
    expect(find.byType(PhotoHostedSquareTile), findsNWidgets(2));
    expect(find.byType(PhotoViewerTopBar), findsNothing);
  });

  // 首屏取数未完成时，托管相册详情只允许一处动画指示：此前是两块占位
  // 各塞一个转圈（同屏两个加载动画）。
  testWidgets('相册详情首屏加载：一屏只有一处动画指示', (tester) async {
    final repository = _MockPhotoRepository();
    _stubRepository(repository, const []);
    when(
      () => repository.getAlbumDetail(any()),
    ).thenAnswer((_) => Completer<PhotoAlbumDetail>().future);

    await _pumpHostedPhone(
      tester,
      initialLocation: '/photos/albums/album-1',
      repository: repository,
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(MobileSkeletonBlock), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空相册托管态：EnvEmptyState 主按钮直达选片页', (tester) async {
    final repository = _MockPhotoRepository();
    _stubRepository(repository, const []);

    await _pumpHostedPhone(
      tester,
      initialLocation: '/photos/albums/album-1',
      repository: repository,
    );

    expect(find.byType(EnvEmptyState), findsOneWidget);
    expect(find.text('No photos in this album'), findsOneWidget);
    await tester.tap(find.text('Add photos'));
    await _settleTap(tester);
    expect(find.byType(PhotoAlbumPhotoPickerPage), findsOneWidget);
  });

  testWidgets('查看器托管态：地名横幅 + 位置副题 + 七动作钮', (tester) async {
    final repository = _MockPhotoRepository();
    _stubRepository(repository, [_photo('p-1', city: 'Bern')]);

    await _pumpHostedPhone(
      tester,
      initialLocation: '/photos/p-1',
      repository: repository,
    );

    expect(find.byType(PhotoViewerHostedHeader), findsOneWidget);
    expect(find.byType(PhotoViewerTopBar), findsNothing);
    // 信息面板默认展开，位置值同样含地名；地名横幅只在头部子树内断言。
    expect(
      find.descendant(
        of: find.byType(PhotoViewerHostedHeader),
        matching: find.text('Bern'),
      ),
      findsOneWidget,
    );
    expect(find.text('1 of 1 · 2024-11-12'), findsOneWidget);
    // 样例 photo-actions：7 个动作钮，无常驻胶片条。信息面板用 AnimatedSlide
    // 滑出屏幕、子树仍在树内，图标断言限定在动作行子树。
    final actions = find.byType(PhotoViewerHostedActions);
    expect(actions, findsOneWidget);
    for (final icon in <IconData>[
      Icons.favorite_border_rounded,
      Icons.share_outlined,
      Icons.download_outlined,
      Icons.edit_outlined,
      Icons.add_rounded,
      Icons.info_outline_rounded,
      Icons.delete_outline_rounded,
    ]) {
      expect(
        find.descendant(of: actions, matching: find.byIcon(icon)),
        findsOneWidget,
        reason: '动作行应包含图标 $icon',
      );
    }
    expect(find.byType(PhotoViewerBottomActions), findsNothing);
  });

  testWidgets('选片页托管态：点选出现对勾舱，全选覆盖已加载候选', (tester) async {
    final repository = _MockPhotoRepository();
    _stubRepository(repository, [_photo('p-1')]);

    await _pumpHostedPhone(
      tester,
      initialLocation: '/photos/albums/album-1/add',
      repository: repository,
    );

    expect(find.byType(MobileModuleHeader), findsOneWidget);
    expect(find.byType(PhotoHostedSquareTile), findsNWidgets(2));
    // 页头返回钮按样例也是矢量尖括号，计数对勾舱时先减掉页头那一枚。
    expect(bodyGlyphCount(tester), 0);

    await tester.tap(find.byType(PhotoHostedSquareTile).first);
    await _settleTap(tester);
    expect(bodyGlyphCount(tester), 1);

    await tester.tap(find.text('Select all'));
    await _settleTap(tester);
    expect(bodyGlyphCount(tester), 2);
  });
}

/// 页头之外的矢量图标数（选片页里就是对勾舱）。
int bodyGlyphCount(WidgetTester tester) {
  final header =
      find
          .descendant(
            of: find.byType(MobileModuleHeader),
            matching: find.byType(OmniIcon),
          )
          .evaluate()
          .length;
  return find.byType(OmniIcon).evaluate().length - header;
}
