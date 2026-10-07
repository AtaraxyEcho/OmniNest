// 幻灯顶栏触控下限回归：关闭键是离开查看器的逃生控件，窄屏下命中区不得
// 低于 48；桌面维持 36 紧凑密度，避免整条顶栏在宽屏被抬高。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_slideshow_chrome.dart';

PhotoItem _photo() {
  return PhotoItem(
    id: 'p-1',
    fileNodeId: 'n-1',
    title: 'IMG_0001.jpg',
    format: 'jpg',
    fileSize: 1,
    metadataStatus: 'MATCHED',
    favorite: false,
    createdAt: DateTime(2026),
  );
}

Future<void> _pumpBar(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: OmniNestTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      // 顶栏自身是 Positioned，必须由 Stack 直接承载（与查看器同构）。
      home: Scaffold(
        body: Stack(
          children: [
            PhotoSlideshowTopBar(
              photo: _photo(),
              current: 0,
              total: 2,
              visible: true,
              showInfo: false,
              showShare: false,
              onClose: () {},
              onToggleFavorite: () {},
              onToggleShare: () {},
              onDownload: () {},
              onToggleInfo: () {},
              onFullscreen: () {},
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 关闭键的按压盒：命中区由 IconButton 的最小约束决定。
final Finder _closeButton = find.ancestor(
  of: find.byIcon(Icons.close_rounded),
  matching: find.byType(IconButton),
);

void main() {
  testWidgets('窄屏关闭键命中区不低于 48', (tester) async {
    await _pumpBar(tester, 390);

    final close = tester.getRect(_closeButton);
    expect(close.width, greaterThanOrEqualTo(48));
    expect(close.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面关闭键保持 36 紧凑密度', (tester) async {
    await _pumpBar(tester, 1280);

    final close = tester.getRect(_closeButton);
    // 桌面不套尺寸盒：命中区仍是 IconButton 自定密度结果，本批不改桌面密度。
    expect(close.width, lessThan(48));
    expect(close.height, lessThan(48));
    expect(tester.takeException(), isNull);
  });
}
