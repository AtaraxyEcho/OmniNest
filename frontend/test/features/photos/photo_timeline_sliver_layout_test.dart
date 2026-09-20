import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_timeline.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_grid_tile.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_timeline_view.dart';

PhotoItem _photo(String id) {
  return PhotoItem(
    id: id,
    fileNodeId: 'file-$id',
    title: 'Photo $id',
    format: 'JPEG',
    fileSize: 1024,
    metadataStatus: 'READY',
    favorite: false,
    createdAt: DateTime(2026, 9),
  );
}

PhotoCenterState _stateWithTimeline() {
  final previews = [_photo('a'), _photo('b'), _photo('c')];
  return PhotoCenterState.empty().copyWith(
    timeline: PhotoTimeline.fromMonthEntries([
      PhotoTimelineMonthEntry(
        year: 2026,
        monthGroup: PhotoMonthGroup(
          month: 9,
          photoCount: previews.length,
          previewPhotos: previews,
        ),
      ),
    ]),
  );
}

void main() {
  testWidgets('时间线月份网格使用 Sliver 布局协议，不抛 RenderViewport 类型错误', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: OmniNestTheme.from(AppThemePalette.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: PhotoTimelineView(
              state: _stateWithTimeline(),
              onOpenPhoto: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 月份预览图应挂载，证明 slivers 子树已按 RenderSliver 协议完成布局。
    expect(find.byType(PhotoGridTile), findsWidgets);
  });
}
