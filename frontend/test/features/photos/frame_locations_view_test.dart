import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_locations_view.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_grid_tile.dart';

/// 伪造的照片中心控制器，返回预置照片列表。
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
  final located = [
    _photo(
      'photo-1',
      location: <String, dynamic>{'country': '中国', 'city': '上海市'},
    ),
    _photo(
      'photo-2',
      location: <String, dynamic>{'country': '中国', 'city': '上海市'},
    ),
    _photo(
      'photo-3',
      location: <String, dynamic>{'country': 'Switzerland', 'city': 'Bern'},
    ),
    _photo('photo-4'),
  ];

  Widget harness(List<PhotoItem> photos) {
    return ProviderScope(
      overrides: [
        photoCenterControllerProvider.overrideWith(
          () => _SeededPhotoCenterController(photos),
        ),
      ],
      child: _materialApp(
        FrameLocationsView(onOpenPhoto: (_) {}, onToggleFavorite: (_) {}),
      ),
    );
  }

  testWidgets('按地点分组渲染卡片并显示张数', (tester) async {
    await _pumpView(tester, harness(located));

    expect(find.text('中国 · 上海市'), findsOneWidget);
    expect(find.text('2 张照片'), findsOneWidget);
    expect(find.text('Switzerland · Bern'), findsOneWidget);
    expect(find.text('1 张照片'), findsOneWidget);
    // 无 GPS 的照片不进入地点视图。
    expect(find.text('Photo photo-4'), findsNothing);
  });

  testWidgets('点击地点卡片进入单地点瀑布流并写入浏览范围', (tester) async {
    ProviderContainer? container;
    await _pumpView(
      tester,
      ProviderScope(
        overrides: [
          photoCenterControllerProvider.overrideWith(
            () => _SeededPhotoCenterController(located),
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

    await tester.tap(find.text('中国 · 上海市'));
    await tester.pumpAndSettle();

    expect(find.text('中国 · 上海市'), findsOneWidget);
    expect(find.byType(PhotoGridTile), findsNWidgets(2));

    // 打开照片时浏览范围写入该地点的全部照片。
    await tester.tap(find.byType(PhotoGridTile).first);
    await tester.pumpAndSettle();
    final scope = container!.read(photoBrowseScopeProvider);
    expect(scope.length, 2);
    expect(scope.every((p) => p.id == 'photo-1' || p.id == 'photo-2'), isTrue);
  });

  testWidgets('返回按钮回到地点卡片网格', (tester) async {
    await _pumpView(tester, harness(located));

    await tester.tap(find.text('中国 · 上海市'));
    await tester.pumpAndSettle();
    expect(find.text('中国 · 上海市'), findsOneWidget);

    await tester.tap(find.text('返回地点列表'));
    await tester.pumpAndSettle();
    expect(find.text('2 张照片'), findsOneWidget);
  });

  testWidgets('全部照片无 GPS 时显示空态', (tester) async {
    final noLocation = [_photo('photo-1'), _photo('photo-2')];
    await _pumpView(tester, harness(noLocation));

    expect(find.byIcon(Icons.place_outlined), findsOneWidget);
  });
}
