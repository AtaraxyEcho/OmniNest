import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/appearance/application/composed_scaler.dart';
import 'package:omninest/app/appearance/application/font_scale_scope.dart';

void main() {
  group('ComposedScaler', () {
    const systemScaler = TextScaler.linear(1.2);

    test('字号按应用档位与系统缩放组合', () {
      const scaler = ComposedScaler(systemScaler, 1.15);
      expect(scaler.scale(16), closeTo(16 * 1.38, 0.0001));
      expect(scaler.scale(0), 0);
    });

    test('textScaleFactor 返回组合后的倍率供 MediaQueryData 相等性比较', () {
      const scaler = ComposedScaler(systemScaler, 1.15);
      // textScaleFactor 为已废弃抽象成员，实现它属于 TextScaler 接口约束。
      // ignore: deprecated_member_use
      expect(scaler.textScaleFactor, closeTo(1.38, 0.0001));
    });

    test('跟随系统档位退化为系统缩放本身', () {
      const scaler = ComposedScaler(systemScaler, 1.0);
      expect(scaler.scale(16), systemScaler.scale(16));
    });

    test('相等性按 systemScaler 与 appScale 判定', () {
      const scaler = ComposedScaler(systemScaler, 1.15);
      expect(scaler, const ComposedScaler(systemScaler, 1.15));
      expect(
        scaler.hashCode,
        const ComposedScaler(systemScaler, 1.15).hashCode,
      );
      expect(scaler, isNot(const ComposedScaler(TextScaler.linear(1.2), 1.3)));
      expect(scaler, isNot(const ComposedScaler(TextScaler.linear(1.0), 1.15)));
    });
  });

  testWidgets('FontScaleScope 暴露系统缩放，仅系统区域剔除应用档位', (tester) async {
    double? ambientScale;
    double? systemOnlyScale;

    await tester.pumpWidget(
      FontScaleScope(
        systemScaler: const TextScaler.linear(1.2),
        child: MediaQuery(
          data: const MediaQueryData(
            textScaler: ComposedScaler(TextScaler.linear(1.2), 1.15),
          ),
          child: Builder(
            builder: (inner) {
              ambientScale = MediaQuery.textScalerOf(inner).scale(16);
              return FontScaleScope.withSystemScaleOnly(
                context: inner,
                child: Builder(
                  builder: (deep) {
                    systemOnlyScale = MediaQuery.textScalerOf(deep).scale(16);
                    return const SizedBox.shrink();
                  },
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(ambientScale, closeTo(16 * 1.38, 0.0001));
    expect(systemOnlyScale, closeTo(16 * 1.2, 0.0001));
  });

  testWidgets('无 FontScaleScope 时回退环境缩放', (tester) async {
    double? scale;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: Builder(
          builder: (inner) {
            return FontScaleScope.withSystemScaleOnly(
              context: inner,
              child: Builder(
                builder: (deep) {
                  scale = MediaQuery.textScalerOf(deep).scale(16);
                  return const SizedBox.shrink();
                },
              ),
            );
          },
        ),
      ),
    );

    expect(scale, closeTo(16 * 1.3, 0.0001));
  });
}
