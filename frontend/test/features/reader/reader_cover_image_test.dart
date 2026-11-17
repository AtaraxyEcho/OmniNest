import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reader_image_provider.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_cover_image.dart';

void main() {
  testWidgets('Portal 无穷尺寸封面使用父布局的有限约束', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coverBytesProvider('reader-item').overrideWith((ref) async => null),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                height: 240,
                child: AuthCoverImage(
                  itemId: 'reader-item',
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AuthCoverImage), findsOneWidget);
  });

  testWidgets('完全无界的封面约束不会转换 Infinity 或 NaN', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coverBytesProvider('reader-item').overrideWith((ref) async => null),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: AuthCoverImage(
                itemId: 'reader-item',
                width: double.infinity,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
