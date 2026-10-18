import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_image.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_image_preview.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  testWidgets('tapping content image opens fullscreen preview', (tester) async {
    // 远程图片按隐私策略不再自动加载/提供预览，这里用可加载的 data URI 验证预览链路。
    final block = ImageBlock(
      src:
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      caption: '说明',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderContentImage(
            block: block,
            settings: ReaderViewSettings(),
            retryCount: 0,
            onRetry: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();

    expect(find.byType(ReaderImagePreview), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ReaderImagePreview),
        matching: find.text('说明'),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderImagePreview), findsNothing);
  });

  testWidgets('残缺占位符走失败态而不是 RangeError', (tester) async {
    // `__IMG_` 只有前缀、长度正好 6：按下标两头各切 6/2 会拿负长度抛 RangeError，
    // 预览整页崩；后缀与长度都必须先校验。
    final block = ImageBlock(src: '__IMG_');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderImagePreview(
            block: block,
            itemId: 'item-1',
            retryCount: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });
}
