import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_viewer_chrome.dart';

PhotoItem _photo({bool favorite = false}) {
  return PhotoItem(
    id: 'photo-1',
    fileNodeId: 'file-photo-1',
    title: 'IMG_0031.jpg',
    format: 'JPEG',
    fileSize: 1024,
    metadataStatus: 'READY',
    favorite: favorite,
    createdAt: DateTime(2026),
  );
}

Future<void> _pumpTopBar(
  WidgetTester tester, {
  required bool favorite,
  required VoidCallback onToggleFavorite,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      theme: OmniNestTheme.from(AppThemePalette.dark),
      home: Scaffold(
        body: PhotoViewerTopBar(
          photo: _photo(favorite: favorite),
          onClose: () {},
          onToggleFavorite: onToggleFavorite,
          onDelete: () {},
          onToggleInfo: () {},
          onAddToAlbum: () {},
          onEdit: () {},
          onSlideshow: () {},
          onDownload: () {},
          onShare: () {},
          showInfo: false,
          compact: true,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('紧凑档更多菜单提供收藏动作并触发回调', (tester) async {
    var toggled = 0;
    await _pumpTopBar(
      tester,
      favorite: false,
      onToggleFavorite: () => toggled++,
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('取消收藏'), findsNothing);

    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();

    expect(toggled, 1);
  });

  testWidgets('已收藏照片在更多菜单显示取消收藏', (tester) async {
    await _pumpTopBar(tester, favorite: true, onToggleFavorite: () {});

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    expect(find.text('取消收藏'), findsOneWidget);
    expect(find.text('收藏'), findsNothing);
  });
}
