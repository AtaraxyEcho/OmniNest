import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/app_loading.dart';

void main() {
  testWidgets('AppLoading 统一渲染一枚居中指示器', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(width: 390, height: 800, child: AppLoading()),
      ),
    );

    final loading = find.byType(AppLoading);
    expect(loading, findsOneWidget);
    expect(
      find.descendant(
        of: loading,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(find.byType(ShaderMask), findsNothing);
  });
}
