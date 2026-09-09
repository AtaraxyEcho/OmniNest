import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_image.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_image_preview.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  testWidgets('tapping content image opens fullscreen preview', (tester) async {
    final block = ImageBlock(src: 'https://example.com/a.png', caption: '说明');
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
}
