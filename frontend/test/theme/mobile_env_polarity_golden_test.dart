// 移动环境色板两极性的真实渲染基线：四张图分别对应
// 「极性配壁纸」与「极性逆壁纸」，后者就是 015 量到的塌方形态，用眼睛确认代价。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'golden_fonts.dart';

const _goldenKey = ValueKey<String>('mobile-env-polarity-golden');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadGoldenFonts);

  final cases =
      <({String name, MobileEnvPalette palette, bool brightWallpaper})>[
        (
          name: 'light_on_bright',
          palette: MobileEnvPalette.light,
          brightWallpaper: true,
        ),
        (
          name: 'dark_on_bright',
          palette: MobileEnvPalette.dark,
          brightWallpaper: true,
        ),
        (
          name: 'dark_on_dim',
          palette: MobileEnvPalette.dark,
          brightWallpaper: false,
        ),
        (
          name: 'light_on_dim',
          palette: MobileEnvPalette.light,
          brightWallpaper: false,
        ),
      ];

  for (final testCase in cases) {
    testWidgets('移动环境极性基线 ${testCase.name}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final base =
          testCase.palette == MobileEnvPalette.light
              ? OmniNestTheme.light()
              : OmniNestTheme.dark();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: base.copyWith(
            extensions: [...base.extensions.values, testCase.palette],
          ),
          home: _PolarityFixture(brightWallpaper: testCase.brightWallpaper),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(_goldenKey),
        matchesGoldenFile('goldens/mobile_env_${testCase.name}.png'),
      );
    });
  }
}

class _PolarityFixture extends StatelessWidget {
  const _PolarityFixture({required this.brightWallpaper});

  final bool brightWallpaper;

  @override
  Widget build(BuildContext context) {
    final env = context.env;
    return Scaffold(
      backgroundColor: env.stage,
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors:
                    brightWallpaper
                        ? const <Color>[Color(0xFFF1F3EF), Color(0xFFD6DCD4)]
                        : const <Color>[Color(0xFF1B2220), Color(0xFF080D0C)],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              key: _goldenKey,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MobileModuleHeader(
                  title: '文件',
                  subtitle: '你的数字工位',
                  backTooltip: '返回',
                  onBack: () {},
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '星期四 · 10 月 8 日',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w700,
                          color: env.inkFaint,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '14:47',
                        style: TextStyle(
                          fontSize: 64,
                          height: 0.98,
                          letterSpacing: -4,
                          color: env.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '18° · 晴 杭州',
                        style: TextStyle(fontSize: 13, color: env.white78),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: env.surfaceGlass,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: env.line09),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '正在播放',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.3,
                            fontWeight: FontWeight.w700,
                            color: env.accentInk,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Weightless',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: env.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Marconi Union · 还剩 6:42',
                          style: TextStyle(fontSize: 11, color: env.inkMuted),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            MobileGlassIconButton(
                              tooltip: '上一首',
                              icon: Icons.skip_previous_rounded,
                              onPressed: () {},
                            ),
                            const SizedBox(width: 10),
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: env.accent,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.play_arrow_rounded,
                                color: env.onAccent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: 0.42,
                                  minHeight: 3,
                                  color: env.accentInk,
                                  backgroundColor: env.line15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Row(
                    children: [
                      Text(
                        '离线优先',
                        style: TextStyle(fontSize: 12, color: env.ink),
                      ),
                      const Spacer(),
                      MobileEnvSwitch(value: true, onChanged: (_) {}),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Container(height: 1, color: env.line13),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Text(
                    '发丝线与次级说明在两种极性下的可见性',
                    style: TextStyle(fontSize: 10, color: env.inkMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
