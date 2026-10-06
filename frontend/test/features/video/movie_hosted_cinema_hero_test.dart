// 托管 For you 影院 hero 配色回归：文本层与双钮走环境墨阶与样例按钮族，
// 不再取工位重设计调色板（主钮 = 样例横幅白底深字，次钮 = 深玻璃描边）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_colors.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_mobile_chips.dart';

MovieContinueWatching _item() {
  return const MovieContinueWatching(
    id: 'v-1',
    title: 'Mirage',
    positionSeconds: 480,
    durationSeconds: 1200,
    progressPercent: 40,
    mediaType: 'MOVIE',
  );
}

Future<void> _pump(
  WidgetTester tester, {
  VoidCallback? onPlay,
  VoidCallback? onInfo,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: OmniNestTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: MobileShellScope(
        hosted: true,
        child: Scaffold(
          backgroundColor: MobileEnvColors.stage,
          body: SingleChildScrollView(
            child: MovieMobileCinemaHero(
              item: _item(),
              metaLine: '8.1 · 2024 · 剧情',
              badgeText: '4K · HDR',
              onPlay: onPlay ?? () {},
              onInfo: onInfo ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Material _buttonMaterial(WidgetTester tester, String label) {
  final candidates =
      find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .evaluate()
          .map((element) => element.widget as Material)
          .where(
            (material) =>
                material.shape is RoundedRectangleBorder &&
                (material.shape as RoundedRectangleBorder).borderRadius ==
                    const BorderRadius.all(Radius.circular(22)),
          )
          .toList();
  expect(candidates, hasLength(1), reason: '$label 只应有一个 hero 按钮容器');
  return candidates.single;
}

void main() {
  testWidgets('主钮米白实底、次钮深玻璃描边', (tester) async {
    await _pump(tester);

    final primary = _buttonMaterial(tester, '续播');
    final secondary = _buttonMaterial(tester, '详情');
    final secondaryShape = secondary.shape as RoundedRectangleBorder;

    expect(primary.color, MobileEnvColors.buttonInk);
    expect(secondary.color, const Color(0x8C121817));
    expect(secondaryShape.side.color, const Color(0x38FFFFFF));
    expect(tester.takeException(), isNull);
  });

  testWidgets('标题用衬线环境墨色，眉标带进度与剩余时长', (tester) async {
    await _pump(tester);

    final title = tester.widget<Text>(find.text('Mirage'));
    expect(title.style?.fontFamily, AppTypography.serifFamily);
    expect(title.style?.color, MobileEnvColors.ink);
    expect(find.textContaining('· 40% ·'), findsOneWidget);
    expect(find.text('8.1 · 2024 · 剧情'), findsOneWidget);
    expect(find.text('4K · HDR'), findsOneWidget);
  });

  testWidgets('续播与详情钮分别回调', (tester) async {
    var played = 0;
    var opened = 0;
    await _pump(tester, onPlay: () => played++, onInfo: () => opened++);

    await tester.tap(find.text('续播'));
    await tester.tap(find.text('详情'));
    await tester.pump();

    expect(played, 1);
    expect(opened, 1);
  });
}
