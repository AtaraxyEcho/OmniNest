import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omninest/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Smoke Test', () {
    testWidgets('app launches without crashing', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 应用启动后至少渲染了一个页面
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}
