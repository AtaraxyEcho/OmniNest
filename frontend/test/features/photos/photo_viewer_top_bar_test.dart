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
          countText: '3 / 24',
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('紧凑档头部只保留幻灯片直达，动作行移至底部', (tester) async {
    await _pumpTopBar(tester, favorite: false, onToggleFavorite: () {});

    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('紧凑档计数与拍摄日期同显', (tester) async {
    await _pumpTopBar(tester, favorite: false, onToggleFavorite: () {});

    expect(find.text('3 / 24 · 2026-01-01'), findsOneWidget);
  });
}
