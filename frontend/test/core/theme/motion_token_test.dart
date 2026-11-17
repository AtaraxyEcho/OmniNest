import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/theme/motion_token.dart';

void main() {
  testWidgets('系统减少动态效果时统一返回零动画时长', (tester) async {
    Duration? resolved;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              resolved = MotionToken.resolve(context, MotionToken.normal);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(resolved, Duration.zero);
  });

  testWidgets('常规模式保留设计系统动画时长', (tester) async {
    Duration? resolved;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            resolved = MotionToken.resolve(context, MotionToken.normal);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(resolved, MotionToken.normal);
  });
}
