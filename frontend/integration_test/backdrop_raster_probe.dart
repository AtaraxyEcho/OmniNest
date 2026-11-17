// Real-GPU raster probe for the glass stack (profile mode, Windows 4K).
//
// Answers one question the widget-test probe cannot: how much does a
// BackdropFilter cost on the GPU, and does it matter whether the backdrop
// underneath is animating? Runs four scenarios against the same window size
// so the per-panel cost and the "backdrop changed this frame" penalty can be
// separated. Scratch verification artifact, not a product test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/theme/desktop/desktop_theme.dart';

const Size _logical = Size(2560, 1392);
const Size _physical = Size(3840, 2088);
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

  Future<void> run(
    WidgetTester tester, {
    required int panels,
    required bool animateBackdrop,
    bool grouped = false,
  }) async {
    build.clear();
    raster.clear();
    span.clear();
    tester.view.physicalSize = _physical;
    tester.view.devicePixelRatio = _dpr;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: _logical, devicePixelRatio: _dpr),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: DesktopTheme.resolve(isDark: true),
          home: _Stage(
            panels: panels,
            animateBackdrop: animateBackdrop,
            grouped: grouped,
          ),
        ),
      ),
    );
    await tester.pump();
    // 入场动画 600ms 结束后再开始计时，避免把首帧与着色器 warm-up 算进去。
    await tester.pump(const Duration(milliseconds: 700));
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  void report(String label) {
    void pct(List<double> v, String name) {
      if (v.isEmpty) {
        print('GLASS_PROBE $label $name n=0');
        return;
      }
      final s = [...v]..sort();
      final avg = s.reduce((a, b) => a + b) / s.length;
      print(
        'GLASS_PROBE $label $name n=${s.length} '
        'avg=${avg.toStringAsFixed(2)} '
        'p95=${s[(s.length * 0.95).floor()].toStringAsFixed(2)} '
        'max=${s.last.toStringAsFixed(2)}',
      );
    }

    pct(build, 'build');
    pct(raster, 'raster');
    pct(span, 'span');
  }

  testWidgets('A: 8 glass panels over an animating backdrop', (tester) async {
    await run(tester, panels: 8, animateBackdrop: true);
    report('A-8panels-animated');
  });

  testWidgets('B: 8 glass panels over a static backdrop', (tester) async {
    await run(tester, panels: 8, animateBackdrop: false);
    report('B-8panels-static');
  });

  testWidgets('C: no panels, animating backdrop (baseline)', (tester) async {
    await run(tester, panels: 0, animateBackdrop: true);
    report('C-0panels-animated');
  });

  testWidgets('D: 4 glass panels over an animating backdrop', (tester) async {
    await run(tester, panels: 4, animateBackdrop: true);
    report('D-4panels-animated');
  });

  testWidgets('E: 8 grouped panels over an animating backdrop', (tester) async {
    await run(tester, panels: 8, animateBackdrop: true, grouped: true);
    report('E-8panels-grouped-animated');
  });
}

/// 固定的「卡片墙」场景：一个覆盖全屏的渐变底（可动画），上面铺 N 块
/// 24σ 的玻璃面板，尺寸与首页卡片一致（400×200，间距 16）。
class _Stage extends StatefulWidget {
  const _Stage({
    required this.panels,
    required this.animateBackdrop,
    this.grouped = false,
  });

  final int panels;
  final bool animateBackdrop;
  final bool grouped;

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animateBackdrop) {
      _drift.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backdrop = RepaintBoundary(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF10202A), Color(0xFF2A3B2E), Color(0xFF1A1520)],
          ),
        ),
      ),
    );
    Widget panels() => Padding(
      padding: const EdgeInsets.all(24),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (var i = 0; i < widget.panels; i++)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter.grouped(
                filterConfig: ImageFilterConfig(
                  desktopGlassFilter(blur: 24, saturation: 1.3),
                ),
                child: Container(
                  width: 400,
                  height: 200,
                  color: const Color(0xFF16201C).withValues(alpha: 0.62),
                  child: Center(
                    child: Text(
                      'panel $i',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    final stack = Stack(
      fit: StackFit.expand,
      children: [
        if (widget.animateBackdrop)
          AnimatedBuilder(
            animation: _drift,
            builder:
                (context, child) => Transform.translate(
                  offset: Offset(40 * _drift.value, 24 * _drift.value),
                  child: child,
                ),
            child: backdrop,
          )
        else
          backdrop,
        panels(),
      ],
    );
    return Scaffold(body: widget.grouped ? BackdropGroup(child: stack) : stack);
  }
}
