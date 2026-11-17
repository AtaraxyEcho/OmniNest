import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/utils/image_decode_width.dart';

void main() {
  group('quantizedDecodeWidth', () {
    test('非法输入回落到 min', () {
      expect(
        quantizedDecodeWidth(
          logicalWidth: 0,
          devicePixelRatio: 2,
          min: 128,
          max: 4096,
        ),
        128,
      );
      expect(
        quantizedDecodeWidth(
          logicalWidth: 800,
          devicePixelRatio: 0,
          min: 128,
          max: 4096,
        ),
        128,
      );
    });

    test('按步长向上量化并夹取上下界', () {
      expect(
        quantizedDecodeWidth(
          logicalWidth: 1000,
          devicePixelRatio: 1,
          step: 256,
          min: 128,
          max: 4096,
        ),
        1024,
      );
      expect(
        quantizedDecodeWidth(
          logicalWidth: 10,
          devicePixelRatio: 1,
          step: 256,
          min: 128,
          max: 4096,
        ),
        256,
      );
      expect(
        quantizedDecodeWidth(
          logicalWidth: 10000,
          devicePixelRatio: 2,
          step: 256,
          min: 128,
          max: 2048,
        ),
        2048,
      );
    });

    test('scale 参与超采样', () {
      expect(
        quantizedDecodeWidth(
          logicalWidth: 400,
          devicePixelRatio: 1,
          step: 128,
          min: 128,
          max: 2048,
          scale: 2,
        ),
        896,
      );
    });
  });

  group('quantizeDecodeTier', () {
    test('吸附到第一个不低于 value 的档位', () {
      const tiers = [720, 1080, 1440, 1920];
      expect(quantizeDecodeTier(700, tiers), 720);
      expect(quantizeDecodeTier(720, tiers), 720);
      expect(quantizeDecodeTier(1200, tiers), 1440);
      expect(quantizeDecodeTier(4000, tiers), 1920);
    });
  });

  group('quantizeDecodePixels', () {
    test('整数像素按步长向上取整', () {
      expect(quantizeDecodePixels(900, step: 256, min: 128, max: 4096), 1024);
      expect(quantizeDecodePixels(1, step: 256, min: 128, max: 4096), 256);
      expect(quantizeDecodePixels(0, step: 256, min: 128, max: 4096), 128);
    });
  });
}
