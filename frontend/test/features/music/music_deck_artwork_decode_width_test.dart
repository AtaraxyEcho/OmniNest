import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';

/// 卡组封面的解码宽度必须按档位量化：宽度随窗口连续变化时，逐像素跟随会为同一张
/// 封面生成大量内存解码键与磁盘缩放条目，并反复触发重解码。
Future<int?> _diskCacheWidthAt(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width * 4, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: OmniNestTheme.from(AppThemePalette.dark),
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: width,
              child: const MusicDeckArtwork(
                title: 'Quantized',
                imageUrl: 'https://example.com/cover.jpg',
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  return tester
      .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
      .maxWidthDiskCache;
}

void main() {
  testWidgets('同一档位内的宽度变化复用同一解码宽度', (tester) async {
    expect(await _diskCacheWidthAt(tester, 300), 320);
    expect(await _diskCacheWidthAt(tester, 316), 320);
  });

  testWidgets('跨过档位边界才换解码宽度', (tester) async {
    expect(await _diskCacheWidthAt(tester, 321), 384);
  });

  testWidgets('小尺寸落到下限档，不随约束继续下探', (tester) async {
    expect(await _diskCacheWidthAt(tester, 44), 128);
  });
}
