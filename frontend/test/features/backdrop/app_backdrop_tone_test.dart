// 壁纸极性判定的守卫：中间调必须留在暗基准，只有明确偏亮且非逆光才翻浅。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_tone.dart';

Uint8List _bands({
  required int topGray,
  required int bottomGray,
  int w = 4,
  int h = 6,
}) {
  final bytes = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    final v = y < h ~/ 2 ? topGray : bottomGray;
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      bytes[i] = v;
      bytes[i + 1] = v;
      bytes[i + 2] = v;
      bytes[i + 3] = 255;
    }
  }
  return bytes;
}

void main() {
  test('相对亮度取 WCAG 定义', () {
    expect(relativeLuminance(255, 255, 255), closeTo(1.0, 0.001));
    expect(relativeLuminance(0, 0, 0), 0);
    // 18% 灰（sRGB 128）的相对亮度约 0.216，不是线性的一半。
    expect(relativeLuminance(128, 128, 128), closeTo(0.216, 0.002));
  });

  test('分带均值按行切上下两半', () {
    final tone = toneFromRgba(
      rgba: _bands(topGray: 240, bottomGray: 24),
      width: 4,
      height: 6,
    );
    expect(tone.topLuminance, greaterThan(tone.bottomLuminance));
    expect(tone.topLuminance, closeTo(relativeLuminance(240, 240, 240), 0.001));
    expect(tone.bottomLuminance, closeTo(relativeLuminance(24, 24, 24), 0.001));
  });

  test('入参不可用时退回暗色而不是抛错', () {
    const dark = AppBackdropTone(topLuminance: 0, bottomLuminance: 0);
    expect(
      toneFromRgba(rgba: Uint8List(0), width: 0, height: 0),
      isA<AppBackdropTone>(),
    );
    expect(
      toneFromRgba(rgba: Uint8List(4), width: 2, height: 2).polarity,
      AppBackdropPolarity.dark,
    );
    expect(dark.polarity, AppBackdropPolarity.dark);
  });

  test('明确偏亮的壁纸翻浅，暗与中间调留在暗基准', () {
    AppBackdropTone toneOf(int gray) => toneFromRgba(
      rgba: _bands(topGray: gray, bottomGray: gray),
      width: 4,
      height: 6,
    );

    expect(toneOf(250).polarity, AppBackdropPolarity.light);
    expect(toneOf(30).polarity, AppBackdropPolarity.dark);
    // 阈值以下：白字与深墨字都够不到 4.5:1 的中间带，不翻。
    expect(toneOf(128).polarity, AppBackdropPolarity.dark);
    expect(toneOf(140).polarity, AppBackdropPolarity.dark);
    expect(toneOf(170).polarity, AppBackdropPolarity.light);
  });

  test('逆光构图（上亮下暗）不翻浅', () {
    final backlit = toneFromRgba(
      rgba: _bands(topGray: 250, bottomGray: 20),
      width: 4,
      height: 6,
    );
    expect(backlit.topLuminance, greaterThan(AppBackdropTone.lightThreshold));
    expect(backlit.polarity, AppBackdropPolarity.dark);
  });
}
