import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_group.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_locations_view.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_grid_tile.dart';

class _MockPhotoRepository extends Mock implements PhotoRepository {}

/// 伪造的照片中心控制器，返回预置的已加载窗口。
class _SeededPhotoCenterController extends PhotoCenterController {
  _SeededPhotoCenterController(this.photos);

  final List<PhotoItem> photos;

  @override
  Future<PhotoCenterState> build() async {
    return PhotoCenterState(
      dashboard: PhotoDashboard.empty(),
      photos: photos,
      favorites: const [],
      albums: const [],
      tab: PhotoTab.all,
      photoTotalElements: photos.length,
    );
  }
}

PhotoItem _photo(String id, {Map<String, dynamic>? location}) {
  return PhotoItem(
    id: id,
    fileNodeId: 'file-$id',
    title: 'Photo $id',
    format: 'JPEG',
    fileSize: 1024,
    metadataStatus: 'READY',
    favorite: false,
    createdAt: DateTime(2026),
    gpsLocation: location,
  );
}

PhotoGroup _group(String key, int count, List<PhotoItem> previews) {
  return PhotoGroup(groupKey: key, photoCount: count, photos: previews);
}

Widget _materialApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    theme: OmniNestTheme.from(AppThemePalette.dark),
    home: Scaffold(body: child),
  );
}

Future<void> _pumpView(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(child);
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  final shanghaiFirst = _photo(
    'photo-1',
    location: <String, dynamic>{'country': '中国', 'city': '上海市'},
  );
  final shanghaiSecond = _photo(
    'photo-2',
    location: <String, dynamic>{'country': '中国', 'city': '上海市'},
  );
  final shanghaiThird = _photo(
    'photo-3',
    location: <String, dynamic>{'country': '中国', 'city': '上海市'},
  );
  final bern = _photo(
    'photo-4',
    location: <String, dynamic>{'country': 'Switzerland', 'city': 'Bern'},
  );
  final noGps = _photo('photo-5');

  /// 服务端分组：上海市共 120 张（窗口里只落了 1 张），Bern 只有预览里的 1 张。
  List<PhotoGroup> serverGroups() => [
    _group('上海市', 120, [shanghaiFirst, shanghaiSecond, shanghaiThird]),
    _group('Bern', 1, [bern]),
  ];

  /// 已加载窗口只覆盖上海市的一张照片，地点视图不能因此漏掉 Bern。
  List<PhotoItem> window() => [shanghaiFirst, noGps];

  void stubGroups(_MockPhotoRepository repository, List<PhotoGroup> groups) {
    when(
      () => repository.getGroups(
        any(),
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer(
      (invocation) async => PhotoGroupPage(
        items: groups,
        page: 0,
        size: 200,
        totalElements: groups.length,
        totalPages: 1,
      ),
    );
  }

  _MockPhotoRepository repositoryWith(List<PhotoGroup> groups) {
    final repository = _MockPhotoRepository();
    stubGroups(repository, groups);
    return repository;
  }

  Widget harness({
    required List<PhotoGroup> groups,
    List<PhotoItem>? photos,
    _MockPhotoRepository? repository,
  }) {
    return ProviderScope(
      overrides: [
        photoRepositoryProvider.overrideWithValue(
          repository ?? repositoryWith(groups),
        ),
        photoCenterControllerProvider.overrideWith(
          () => _SeededPhotoCenterController(photos ?? window()),
        ),
      ],
      child: _materialApp(
        FrameLocationsView(onOpenPhoto: (_) {}, onToggleFavorite: (_) {}),
      ),
    );
  }

  testWidgets('地点卡片取服务端分组，张数用服务端总数', (tester) async {
    final repository = repositoryWith(serverGroups());
    await _pumpView(
      tester,
      harness(groups: serverGroups(), repository: repository),
    );

    expect(find.text('上海市'), findsOneWidget);
    expect(find.text('120 张照片'), findsOneWidget);
    // Bern 的照片根本没进已加载窗口，仍必须作为一个地点出现。
    expect(find.text('Bern'), findsOneWidget);
    expect(find.text('1 张照片'), findsOneWidget);
    // 无 GPS 的照片不再被静默丢弃在外：服务端未给未知位置分组时不显示。
    expect(find.text('Photo photo-5'), findsNothing);
    // 维度必须是 LOCATION：拿错维度等于把日期分组当地点渲染。
    verify(() => repository.getGroups('LOCATION', size: 200)).called(1);
  });

  testWidgets('点击地点卡片进入单地点瀑布流并写入浏览范围', (tester) async {
    ProviderContainer? container;
    final groups = serverGroups();
    final repository = _MockPhotoRepository();
    when(
      () => repository.getGroups(
        any(),
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer(
      (invocation) async => PhotoGroupPage(
        items: groups,
        page: 0,
        size: 200,
        totalElements: groups.length,
        totalPages: 1,
      ),
    );
    await _pumpView(
      tester,
      ProviderScope(
        overrides: [
          photoRepositoryProvider.overrideWithValue(repository),
          photoCenterControllerProvider.overrideWith(
            () => _SeededPhotoCenterController(window()),
          ),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return _materialApp(
              FrameLocationsView(onOpenPhoto: (_) {}, onToggleFavorite: (_) {}),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('上海市'));
    await tester.pumpAndSettle();

    expect(find.text('上海市'), findsOneWidget);
    // 明细 = 窗口内同城照片 + 服务端预览补齐，同一照片不重复渲染。
    expect(find.byType(PhotoGridTile), findsNWidgets(3));

    await tester.tap(find.byType(PhotoGridTile).first);
    await tester.pumpAndSettle();
    final scope = container!.read(photoBrowseScopeProvider);
    expect(scope.source, PhotoBrowseSource.locations);
    expect(scope.sourceKey, '上海市');
    expect(scope.photos.map((photo) => photo.id), [
      'photo-1',
      'photo-2',
      'photo-3',
    ]);
  });

  testWidgets('返回按钮回到地点卡片网格', (tester) async {
    await _pumpView(tester, harness(groups: serverGroups()));

    await tester.tap(find.text('上海市'));
    await tester.pumpAndSettle();
    expect(find.text('上海市'), findsOneWidget);

    await tester.tap(find.text('返回地点列表'));
    await tester.pumpAndSettle();
    expect(find.text('120 张照片'), findsOneWidget);
  });

  testWidgets('服务端没有地点分组时显示空态', (tester) async {
    await _pumpView(tester, harness(groups: const <PhotoGroup>[]));

    expect(find.byIcon(Icons.place_outlined), findsOneWidget);
  });

  testWidgets('未知位置按服务端桶名归组，明细补齐窗口内无 GPS 照片', (tester) async {
    await _pumpView(
      tester,
      harness(
        groups: [_group('未知位置', 2, const <PhotoItem>[])],
        photos: [noGps],
      ),
    );

    await tester.tap(find.text('未知位置'));
    await tester.pumpAndSettle();

    expect(find.byType(PhotoGridTile), findsNWidgets(1));
    // 明细计数只说已渲染的张数：卡片上的服务端总数（2）不该在这里冒充可见结果。
    expect(find.text('1 张照片'), findsOneWidget);
  });
}
