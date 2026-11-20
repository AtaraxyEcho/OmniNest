// Real-GPU raster probe (profile mode, Windows). Measures FrameTiming of the
// ambient layer alone at 4K, animating vs static. Scratch verification artifact.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omninest/app/desktop/desktop_ambient.dart';
import 'package:omninest/app/theme/desktop/desktop_theme.dart';

const Size _logical = Size(2560, 1392);
const double _dpr = 1.5;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final build = <double>[];
  final raster = <double>[];
  final span = <double>[];
  binding.addTimingsCallback((timings) {
    for (final t in timings) {
      build.add(t.buildDuration.inMicroseconds / 1000.0);
      raster.add(t.rasterDuration.inMicroseconds / 1000.0);
      span.add(t.totalSpan.inMicroseconds / 1000.0);
    }
  });

  Future<void> pumpAmbient(WidgetTester tester, {required bool reduce}) async {
    build.clear();
    raster.clear();
    span.clear();
    tester.view.physicalSize = const Size(3840, 2088);
    tester.view.devicePixelRatio = _dpr;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: _logical, devicePixelRatio: _dpr),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: DesktopTheme.resolve(isDark: true),
          home: Scaffold(
            body: DesktopAmbient(
              imageUrl: 'https://example.test/cover.jpg',
              intensity: 70,
              reduceMotion: reduce,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  void report(String label) {
    void pct(List<double> v, String name) {
      if (v.isEmpty) {
        // ignore: avoid_print
        print('RASTER_PROBE $label $name n=0');
        return;
      }
      final s = [...v]..sort();
      final avg = s.reduce((a, b) => a + b) / s.length;
      // 探针输出要被外部脚本按前缀逐行解析：debugPrint 会节流并重排，
      // 采样行必须原样落在设备日志里。
      // ignore: avoid_print
      print(
        'RASTER_PROBE $label $name n=${s.length} '
        'avg=${avg.toStringAsFixed(2)} '
        'p95=${s[(s.length * 0.95).floor()].toStringAsFixed(2)} '
        'max=${s.last.toStringAsFixed(2)}',
      );
    }

    pct(build, 'build_ms');
    pct(raster, 'raster_ms');
    pct(span, 'span_ms');
  }

  testWidgets('ambient animating real raster', (tester) async {
    await pumpAmbient(tester, reduce: false);
    report('ambient-on');
  });

  testWidgets('ambient static real raster', (tester) async {
    await pumpAmbient(tester, reduce: true);
    report('ambient-static');
  });
}
