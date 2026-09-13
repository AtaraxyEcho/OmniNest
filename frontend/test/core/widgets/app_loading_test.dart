import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/app_loading.dart';

void main() {
  testWidgets('AppLoading 统一渲染居中指示器', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(width: 390, height: 800, child: AppLoading.grid()),
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

  testWidgets('AppLoading.detail 与 simple 同样为居中指示器', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppLoading.detail())),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppLoading.simple())),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
