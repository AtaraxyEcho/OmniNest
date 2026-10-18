import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reader_image_provider.dart';
import 'package:omninest/features/reader/data/reader_content_preprocessor.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_image.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 1×1 透明 PNG，用于验证本地缓存占位符仍然正常渲染。
final Uint8List _tinyPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0xDA, 0x63, 0xFC, 0xCF, 0xC0, 0x50,
  0x0F, 0x00, 0x04, 0x85, 0x01, 0x80, 0x84, 0xA9,
  0x8C, 0x21, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Widget _host(ImageBlock block, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 600,
          child: ReaderContentImage(
            block: block,
            settings: ReaderViewSettings(),
            retryCount: 0,
            onRetry: () {},
            itemId: 'item-1',
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('远程图片地址被判定为不可自动加载', () {
    expect(isRemoteReaderImageSource('https://example.com/a.png'), isTrue);
    expect(isRemoteReaderImageSource('http://example.com/a.png'), isTrue);
    expect(isRemoteReaderImageSource('__IMG_images/a.png__'), isFalse);
    expect(isRemoteReaderImageSource('data:image/png;base64,AAAA'), isFalse);
  });

  test('预处理器不把远程图片改写成本地缓存占位符', () async {
    final result = await ReaderContentPreprocessor.preprocessForStorage(
      itemId: 'item-1',
      xhtml:
          '<body><p><img src="https://tracker.example.com/pixel.png"/></p>'
          '</body>',
    );

    expect(result.html, contains('https://tracker.example.com/pixel.png'));
    expect(result.html.contains('__IMG_'), isFalse);
    expect(
      isRemoteReaderImageSource('https://tracker.example.com/pixel.png'),
      isTrue,
    );
  });

  testWidgets('远程图片显示破图占位，不构建网络图片', (tester) async {
    await tester.pumpWidget(
      _host(ImageBlock(src: 'https://tracker.example.com/pixel.png')),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });

  testWidgets('本地缓存占位符仍按缓存字节渲染', (tester) async {
    await tester.pumpWidget(
      _host(
        ImageBlock(src: '__IMG_images/a.png__'),
        overrides: [
          readerCachedImageProvider.overrideWith((ref, request) async {
            return _tinyPng;
          }),
        ],
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
  });
}
