import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/brand_logo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('应用内品牌标记已打包且必须带透明像素', () async {
    final data = await rootBundle.load(BrandLogo.assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = (await codec.getNextFrame()).image;
    addTearDown(frame.dispose);

    expect(frame.width, frame.height, reason: '标记是方形构图');

    final pixels = await frame.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    expect(pixels, isNotNull);
    final bytes = pixels!.buffer.asUint8List();
    var transparent = 0;
    for (var i = 3; i < bytes.length; i += 4) {
      if (bytes[i] < 8) {
        transparent++;
      }
    }

    // 深色底块在浅色主题下会读成一块黑方框，应用内资源不允许换成不透明图。
    expect(
      transparent / (frame.width * frame.height),
      greaterThan(0.1),
      reason: '品牌标记必须是透明底',
    );
  });
}
