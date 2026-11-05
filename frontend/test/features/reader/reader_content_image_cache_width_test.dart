import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/utils/image_decode_width.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_image.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 1x1 透明 PNG，足够让 data URI 走真实解码路径。
const String _onePixelPng =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  testWidgets('正文插图按量化后的解码宽度解码，避免全分辨率位图常驻', (tester) async {
    const logicalWidth = 320.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: logicalWidth,
            child: ReaderContentImage(
              block: ImageBlock(src: _onePixelPng),
              settings: ReaderViewSettings(),
              retryCount: 0,
              onRetry: () {},
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image;
    expect(provider, isA<ResizeImage>());
    expect(
      (provider as ResizeImage).width,
      quantizedDecodeWidth(
        logicalWidth: logicalWidth,
        devicePixelRatio: tester.view.devicePixelRatio,
      ),
    );
  });
}
