import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';

void main() {
  testWidgets('MobileShellScope 只向子树暴露壳层承载状态', (tester) async {
    bool? hosted;
    await tester.pumpWidget(
      MaterialApp(
        home: MobileShellScope(
          hosted: true,
          child: Builder(
            builder: (context) {
              hosted = MobileShellScope.isHosted(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(hosted, isTrue);
  });
}
