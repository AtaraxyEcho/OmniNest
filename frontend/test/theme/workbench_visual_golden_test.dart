import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';
import 'package:omninest/core/widgets/workbench_top_bar.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_glass_components.dart';

const _goldenKey = ValueKey<String>('workbench-golden');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final interLoader =
        FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Inter-Medium.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Inter-Bold.ttf'));
    final notoSansLoader =
        FontLoader('NotoSansSC')
          ..addFont(rootBundle.load('assets/fonts/NotoSansSC-400.ttf'))
          ..addFont(rootBundle.load('assets/fonts/NotoSansSC-500.ttf'))
          ..addFont(rootBundle.load('assets/fonts/NotoSansSC-600.ttf'))
          ..addFont(rootBundle.load('assets/fonts/NotoSansSC-700.ttf'));
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(_loadMaterialIcons());
    await Future.wait(<Future<void>>[
      interLoader.load(),
      notoSansLoader.load(),
      iconLoader.load(),
    ]);
  });

  final cases = <({String name, Size size, Brightness brightness})>[
    (
      name: 'desktop_light',
      size: const Size(1280, 800),
      brightness: Brightness.light,
    ),
    (
      name: 'desktop_dark',
      size: const Size(1280, 800),
      brightness: Brightness.dark,
    ),
    (
      name: 'mobile_light',
      size: const Size(390, 844),
      brightness: Brightness.light,
    ),
    (
      name: 'mobile_dark',
      size: const Size(390, 844),
      brightness: Brightness.dark,
    ),
  ];

  for (final testCase in cases) {
    testWidgets('工作台视觉基线 ${testCase.name}', (tester) async {
      await tester.binding.setSurfaceSize(testCase.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme:
              testCase.brightness == Brightness.light
                  ? OmniNestTheme.light()
                  : OmniNestTheme.dark(),
          home: const _WorkbenchGoldenFixture(),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(_goldenKey),
        matchesGoldenFile('goldens/workbench_${testCase.name}.png'),
      );
    });
  }
}

Future<ByteData> _loadMaterialIcons() async {
  var directory = File(Platform.resolvedExecutable).parent;
  final separator = Platform.pathSeparator;
  for (var level = 0; level < 8; level++) {
    final fontFile = File(
      <String>[
        directory.path,
        'bin',
        'cache',
        'artifacts',
        'material_fonts',
        'MaterialIcons-Regular.otf',
      ].join(separator),
    );
    if (await fontFile.exists()) {
      final bytes = await fontFile.readAsBytes();
      return ByteData.sublistView(Uint8List.fromList(bytes));
    }
    directory = directory.parent;
  }
  throw StateError('无法定位 Flutter Material Icons 字体。');
}

class _WorkbenchGoldenFixture extends StatelessWidget {
  const _WorkbenchGoldenFixture();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      key: _goldenKey,
      child: Scaffold(
        body: Column(
          children: <Widget>[
            WorkbenchTopBar(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'O',
                        style: TextStyle(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'OmniNest',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '通知',
                      onPressed: () {},
                      icon: const Icon(Icons.notifications_none_rounded),
                    ),
                    IconButton(
                      tooltip: '账户',
                      onPressed: () {},
                      icon: const Icon(Icons.account_circle_outlined),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final desktop = constraints.maxWidth >= 720;
                  if (desktop) {
                    return Row(
                      children: <Widget>[
                        const SizedBox(width: 220, child: _GoldenNavigation()),
                        VerticalDivider(width: 1, color: scheme.outlineVariant),
                        const Expanded(child: _GoldenContent()),
                      ],
                    );
                  }
                  return const Column(
                    children: <Widget>[
                      Expanded(child: _GoldenContent()),
                      _GoldenMobileDock(),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoldenNavigation extends StatelessWidget {
  const _GoldenNavigation();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _GoldenNavItem(
              icon: Icons.dashboard_rounded,
              label: '总览',
              selected: true,
            ),
            const _GoldenNavItem(icon: Icons.folder_outlined, label: '文件'),
            const _GoldenNavItem(icon: Icons.music_note_rounded, label: '音乐'),
            const _GoldenNavItem(icon: Icons.menu_book_rounded, label: '阅读'),
            const _GoldenNavItem(icon: Icons.movie_outlined, label: '影视'),
            const Spacer(),
            Divider(color: scheme.outlineVariant),
            const _GoldenNavItem(icon: Icons.settings_outlined, label: '设置'),
          ],
        ),
      ),
    );
  }
}

class _GoldenNavItem extends StatelessWidget {
  const _GoldenNavItem({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoldenContent extends StatelessWidget {
  const _GoldenContent();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '数字生活工作台',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '文件、媒体与阅读状态保持同步。',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('新建任务'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 620;
                  final children = <Widget>[
                    const Expanded(
                      child: _GoldenStatusPanel(
                        icon: Icons.cloud_done_outlined,
                        title: '同步完成',
                        detail: '最后更新于 10:24',
                      ),
                    ),
                    const SizedBox(width: 12, height: 12),
                    const Expanded(
                      child: _GoldenStatusPanel(
                        icon: Icons.storage_rounded,
                        title: '存储空间',
                        detail: '已使用 38%',
                      ),
                    ),
                  ];
                  return stacked
                      ? Column(
                        children:
                            children
                                .map(
                                  (child) =>
                                      child is Expanded ? child.child : child,
                                )
                                .toList(),
                      )
                      : Row(children: children);
                },
              ),
              const SizedBox(height: 16),
              PortalGlassCard(
                shadow: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '继续使用',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const _GoldenRecentItem(),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              MusicDeckGlass(
                opacity: 0.72,
                blur: 0,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.graphic_eq_rounded,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '正在播放',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'OmniNest Radio · 03:18',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      tooltip: '播放',
                      onPressed: () {},
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoldenStatusPanel extends StatelessWidget {
  const _GoldenStatusPanel({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return WorkbenchPanel(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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

class _GoldenRecentItem extends StatelessWidget {
  const _GoldenRecentItem();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            Icons.description_outlined,
            color: scheme.onTertiaryContainer,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '年度资料整理计划',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '文件 · 2 分钟前',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded),
      ],
    );
  }
}

class _GoldenMobileDock extends StatelessWidget {
  const _GoldenMobileDock();

  @override
  Widget build(BuildContext context) {
    return PortalGlassDock(
      currentIndex: 0,
      onTap: (_) {},
      items: const <PortalGlassDockItem>[
        PortalGlassDockItem(
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard_rounded,
          label: '总览',
        ),
        PortalGlassDockItem(
          icon: Icons.folder_outlined,
          selectedIcon: Icons.folder_rounded,
          label: '文件',
        ),
        PortalGlassDockItem(
          icon: Icons.music_note_outlined,
          selectedIcon: Icons.music_note_rounded,
          label: '音乐',
        ),
        PortalGlassDockItem(
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
          label: '账户',
        ),
      ],
    );
  }
}
